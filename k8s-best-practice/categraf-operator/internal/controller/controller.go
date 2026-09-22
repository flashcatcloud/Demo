package controller

import (
	"context"
	"fmt"
	appsv1 "k8s.io/api/apps/v1"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/flashcat/categraf-operator/internal/config"
	"github.com/flashcat/categraf-operator/internal/flashcat"
)

// PendingItem represents a device waiting for cleanup.
type PendingItem struct {
	Ident        string
	NodeName     string
	DeletedAt    time.Time
	WaitDuration time.Duration
}

// Controller watches Node deletion events and manages the lifecycle of
// Flashcat device cleanup.
type Controller struct {
	client client.Client
	config *config.Config
	fc     *flashcat.Client

	queue   map[string]*PendingItem // keyed by ident
	queueMu sync.RWMutex
}

// New creates a Controller.
func New(cl client.Client, cfg *config.Config, fc *flashcat.Client) *Controller {
	return &Controller{
		client: cl,
		config: cfg,
		fc:     fc,
		queue:  make(map[string]*PendingItem),
	}
}

// Run starts the periodic cleanup loop.  Blocks until ctx is cancelled.
func (c *Controller) Run(ctx context.Context) error {
	lg := log.FromContext(ctx)

	c.recoverFromFlashcat(ctx)
	c.reconcileMissingNodes(ctx)

	lg.Info("cleanup loop started",
		"interval", c.config.ReconcileInterval,
		"stale_node_threshold", c.config.MaxNodeStaleDuration,
	)

	ticker := time.NewTicker(c.config.ReconcileInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			c.processStaleNodes(ctx)
			c.processCleanups(ctx)
			c.recoverFromFlashcat(ctx)
			c.reconcileMissingNodes(ctx)
		case <-ctx.Done():
			return nil
		}
	}
}

// ---- shared tag + queue logic ----

func (c *Controller) tagAndQueue(ctx context.Context, ident, nodeName string, deletedAt time.Time) {
	// 只打 gone 和 deleted_at 标签。
	// cluster 标签由 categraf 的 host_tags 自带，不需要代码再打。
	tags := []string{
		fmt.Sprintf("%s=true", c.config.TagGoneKey),
		fmt.Sprintf("%s=%d", c.config.TagDeletedAtKey, deletedAt.UnixMilli()),
	}
	if err := c.fc.TagTarget(ident, tags); err != nil {
		if !isDuplicateTagKeyErr(err) {
			ctrl.Log.WithName("controller").Error(err, "tagging target failed", "ident", ident, "node", nodeName)
			return
		}
		// 设备已带这些标签（例如删除尚未传播、reconcile 重新发现）。
		// 读取已有的 deleted_at，按原时间入队，避免重新计时。
		if t, gerr := c.fc.GetTargetByIdent(ident, nil); gerr == nil {
			deletedAt = findDeletedAt(t.Tags, c.config.TagDeletedAtKey)
		}
		ctrl.Log.WithName("controller").Info("target already tagged, queueing with existing deletedAt",
			"ident", ident, "node", nodeName, "deletedAt", deletedAt)
	}

	c.queueMu.Lock()
	c.queue[ident] = &PendingItem{
		Ident:        ident,
		NodeName:     nodeName,
		DeletedAt:    deletedAt,
		WaitDuration: c.config.DefaultWaitDuration,
	}
	c.queueMu.Unlock()

	ctrl.Log.WithName("controller").Info("target tagged and queued", "ident", ident, "node", nodeName)
}

// OnNodeDeleted handles a Node deletion event from the informer.
func (c *Controller) OnNodeDeleted(node *corev1.Node) {
	ident := node.Name

	c.queueMu.RLock()
	_, exists := c.queue[ident]
	c.queueMu.RUnlock()
	if exists {
		return
	}

	c.tagAndQueue(context.Background(), ident, node.Name, time.Now())
}

// OnCategrafDaemonSetDeleted handles deletion of the categraf DaemonSet while
// the operator is still running (manual `kubectl delete daemonset`, accidental
// deletion). Full chart-uninstall cleanup is handled by the pre-delete hook via
// RunCleanupOnce; this path is a best-effort fallback for when the operator is
// alive and only the DaemonSet is removed.
func (c *Controller) OnCategrafDaemonSetDeleted(ctx context.Context, ds *appsv1.DaemonSet) {
	lg := log.FromContext(ctx)

	if ds.Name != c.config.CategrafDaemonSetName {
		return
	}

	// Double-check: re-query the API to confirm the DaemonSet is really gone.
	var probe appsv1.DaemonSet
	err := c.client.Get(ctx, types.NamespacedName{
		Name:      c.config.CategrafDaemonSetName,
		Namespace: c.config.Namespace,
	}, &probe)
	if err == nil {
		lg.Info("daemonset still exists, skipping cleanup", "name", ds.Name, "namespace", ds.Namespace)
		return
	}
	if !apierrors.IsNotFound(err) {
		lg.Error(err, "failed to check daemonset existence, skipping cleanup")
		return
	}

	if !c.config.CleanupNodeCategraf {
		lg.Info("nodeAgent cleanup is disabled, skipping Flashcat cleanup",
			"daemonset", ds.Name, "cluster", c.config.ClusterName)
		return
	}

	lg.Info("categraf daemonset deleted, starting Flashcat cleanup",
		"daemonset", ds.Name, "cluster", c.config.ClusterName)

	var cleanupErrs []error

	// The DaemonSet is already gone, so the agents are shutting down. Wait for
	// their heartbeats to stop before deleting targets, otherwise the devices
	// would re-register on the next heartbeat.
	if c.config.CleanupNodeCategraf {
		if err := c.waitHeartbeatsStopped(ctx, "nodeAgent"); err != nil {
			lg.Error(err, "nodeAgent heartbeat wait failed")
			cleanupErrs = append(cleanupErrs, err)
		} else if err := c.deleteClusterTargets(ctx, "nodeAgent"); err != nil {
			lg.Error(err, "nodeAgent target cleanup failed")
			cleanupErrs = append(cleanupErrs, err)
		}
	}

	// NOTE: ksmAgent cleanup is intentionally not performed here. The ksm
	// StatefulSet is only stopped during a full chart uninstall (pre-delete
	// hook). Deleting ksm targets while the StatefulSet still runs would make
	// them re-register on the next heartbeat.

	if len(cleanupErrs) > 0 {
		lg.Error(cleanupErrs[0], "Flashcat cleanup completed with errors", "error_count", len(cleanupErrs))
	}
}

// RunCleanupOnce performs the full uninstall cleanup from the Helm pre-delete
// hook (operator --cleanup-once): stop node/ksm workloads, wait for heartbeats
// to stop, then delete this cluster's targets. Unlike
// OnCategrafDaemonSetDeleted it does not depend on the operator being alive
// when the workloads are removed.
func (c *Controller) RunCleanupOnce(ctx context.Context) error {
	lg := log.FromContext(ctx)

	if !c.config.CleanupNodeCategraf && !c.config.CleanupKsmCategraf {
		lg.Info("all cleanup flags are false, nothing to clean")
		return nil
	}

	lg.Info("cleanup-once started",
		"cluster", c.config.ClusterName,
		"cleanup_node_categraf", c.config.CleanupNodeCategraf,
		"cleanup_ksm_categraf", c.config.CleanupKsmCategraf)

	var errs []error

	// 0. Stop the operator itself first so its DaemonSet-deletion informer
	// fallback cannot race this hook on the same Flashcat deletions.
	if c.config.CategrafOperatorDeploymentName != "" {
		if err := c.deleteDeployment(ctx); err != nil {
			errs = append(errs, fmt.Errorf("stop operator Deployment: %w", err))
		}
	}

	// 1. Stop workloads (idempotent; NotFound is fine — helm may race us).
	if c.config.CleanupNodeCategraf {
		if err := c.deleteDaemonSet(ctx); err != nil {
			errs = append(errs, fmt.Errorf("stop nodeAgent DaemonSet: %w", err))
		}
	}
	if c.config.CleanupKsmCategraf {
		if err := c.deleteStatefulSet(ctx); err != nil {
			errs = append(errs, fmt.Errorf("stop ksmAgent StatefulSet: %w", err))
		}
	}

	// 2. Wait for heartbeats to stop, then delete targets — fail closed: if the
	// heartbeat wait fails we do NOT delete (devices would re-register).
	if c.config.CleanupNodeCategraf {
		if err := c.waitHeartbeatsStopped(ctx, "nodeAgent"); err != nil {
			errs = append(errs, fmt.Errorf("nodeAgent heartbeat wait: %w", err))
		} else if err := c.deleteClusterTargets(ctx, "nodeAgent"); err != nil {
			errs = append(errs, fmt.Errorf("nodeAgent target cleanup: %w", err))
		}
	}
	if c.config.CleanupKsmCategraf {
		if err := c.waitHeartbeatsStopped(ctx, "ksmAgent"); err != nil {
			errs = append(errs, fmt.Errorf("ksmAgent heartbeat wait: %w", err))
		} else if err := c.deleteClusterTargets(ctx, "ksmAgent"); err != nil {
			errs = append(errs, fmt.Errorf("ksmAgent target cleanup: %w", err))
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("cleanup-once finished with %d error(s), first: %w", len(errs), errs[0])
	}
	lg.Info("cleanup-once completed")
	return nil
}

// deleteDeployment deletes the operator's own Deployment. NotFound is ignored.
func (c *Controller) deleteDeployment(ctx context.Context) error {
	d := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: c.config.CategrafOperatorDeploymentName, Namespace: c.config.Namespace}}
	if err := c.client.Delete(ctx, d); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	log.FromContext(ctx).Info("operator Deployment deletion requested",
		"name", c.config.CategrafOperatorDeploymentName, "namespace", c.config.Namespace)
	return nil
}

// deleteDaemonSet deletes the nodeAgent DaemonSet. NotFound is ignored.
func (c *Controller) deleteDaemonSet(ctx context.Context) error {
	ds := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: c.config.CategrafDaemonSetName, Namespace: c.config.Namespace}}
	if err := c.client.Delete(ctx, ds); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	log.FromContext(ctx).Info("nodeAgent DaemonSet deletion requested",
		"name", c.config.CategrafDaemonSetName, "namespace", c.config.Namespace)
	return nil
}

// deleteStatefulSet deletes the ksmAgent StatefulSet. NotFound is ignored.
func (c *Controller) deleteStatefulSet(ctx context.Context) error {
	ss := &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: c.config.CategrafKsmStatefulSetName, Namespace: c.config.Namespace}}
	if err := c.client.Delete(ctx, ss); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	log.FromContext(ctx).Info("ksmAgent StatefulSet deletion requested",
		"name", c.config.CategrafKsmStatefulSetName, "namespace", c.config.Namespace)
	return nil
}

// agentTargets lists this cluster's Flashcat targets that carry the given
// categraf agent-type tag ("nodeAgent" / "ksmAgent").
func (c *Controller) agentTargets(ctx context.Context, agentType string) ([]flashcat.Target, error) {
	targets, err := c.fc.ListTargetsByCluster(c.config.ClusterName)
	if err != nil {
		return nil, fmt.Errorf("list targets by cluster %q: %w", c.config.ClusterName, err)
	}
	var matched []flashcat.Target
	for _, t := range targets {
		if t.TagsMaps != nil && t.TagsMaps["categraf"] == agentType {
			matched = append(matched, t)
		}
	}
	return matched, nil
}

// waitHeartbeatsStopped polls Flashcat until every target of the given agent
// type in this cluster has stopped heartbeating (TargetUp==0 or last heartbeat
// older than interval×factor), or the timeout elapses.
func (c *Controller) waitHeartbeatsStopped(ctx context.Context, agentType string) error {
	lg := log.FromContext(ctx)

	timeout := c.config.CleanupHeartbeatTimeout
	if timeout <= 0 {
		timeout = 2 * time.Minute
	}
	deadline := time.Now().Add(timeout)

	for {
		targets, err := c.agentTargets(ctx, agentType)
		if err != nil {
			if time.Now().After(deadline) {
				return fmt.Errorf("list %s targets: %w", agentType, err)
			}
			lg.Error(err, "heartbeat wait: listing targets failed, retrying", "agent_type", agentType)
		} else if len(targets) == 0 {
			lg.Info("no targets to wait for", "agent_type", agentType)
			return nil
		} else {
			threshold := time.Now().Add(-time.Duration(c.config.HeartbeatInterval) * time.Duration(c.config.HeartbeatStopFactor))
			stopped := true
			for _, t := range targets {
				if !targetHeartbeatStopped(t, threshold) {
					stopped = false
					break
				}
			}
			if stopped {
				lg.Info("all heartbeats stopped", "agent_type", agentType, "targets", len(targets))
				return nil
			}
		}

		if time.Now().After(deadline) {
			return fmt.Errorf("timed out after %s waiting for %s target heartbeats to stop", timeout, agentType)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(5 * time.Second):
		}
	}
}

// targetHeartbeatStopped reports whether a target's heartbeat is considered
// stopped. TargetUp==0 means Flashcat already marked it down.
func targetHeartbeatStopped(t flashcat.Target, threshold time.Time) bool {
	if t.TargetUp == 0 {
		return true
	}
	return t.Unixtime < threshold.UnixMilli()
}

// deleteClusterTargets deletes all targets of the given agent type belonging to
// this cluster, after per-ident safety checks.
func (c *Controller) deleteClusterTargets(ctx context.Context, agentType string) error {
	lg := log.FromContext(ctx)

	targets, err := c.agentTargets(ctx, agentType)
	if err != nil {
		return err
	}

	var deleteErrs int
	for _, t := range targets {
		if err := c.deleteTargetIfSafe(ctx, t); err != nil {
			lg.Error(err, "failed to delete target", "ident", t.Ident)
			deleteErrs++
		} else {
			lg.Info("deleted target", "ident", t.Ident)
		}
	}

	lg.Info("target cleanup completed",
		"cluster", c.config.ClusterName,
		"agent_type", agentType,
		"total_targets", len(targets),
		"delete_errors", deleteErrs,
	)

	if deleteErrs > 0 {
		return fmt.Errorf("%d target deletions failed", deleteErrs)
	}
	return nil
}

// deleteTargetIfSafe deletes a single Flashcat target after confirming the ident
// is unique cluster-wide and, when tagged, belongs to this cluster. This guards
// multi-cluster setups where idents could collide: DeleteTarget removes every
// device sharing the ident.
func (c *Controller) deleteTargetIfSafe(ctx context.Context, t flashcat.Target) error {
	all, err := c.fc.ListTargetsByIdent(t.Ident, nil)
	if err != nil {
		return fmt.Errorf("ident uniqueness check: %w", err)
	}
	if len(all) == 0 {
		// Already gone — e.g. the informer fallback path or a previous hook
		// attempt deleted it concurrently. Treat as success (idempotent).
		return nil
	}
	if len(all) != 1 {
		return fmt.Errorf("ident %q is shared by %d device(s), aborting deletion", t.Ident, len(all))
	}
	if cluster := tagsMapCluster(all[0]); cluster != "" && cluster != c.config.ClusterName {
		return fmt.Errorf("ident %q belongs to cluster %q, not %q, aborting deletion", t.Ident, cluster, c.config.ClusterName)
	}
	return c.fc.DeleteTarget(t.Ident)
}

// tagsMapCluster returns the value of the "cluster" tag in tags_maps.
func tagsMapCluster(t flashcat.Target) string {
	if t.TagsMaps == nil {
		return ""
	}
	return t.TagsMaps["cluster"]
}

// ---- stale node detection ----

func (c *Controller) processStaleNodes(ctx context.Context) {
	if c.config.MaxNodeStaleDuration <= 0 {
		return
	}

	lg := log.FromContext(ctx)

	var nodes corev1.NodeList
	if err := c.client.List(ctx, &nodes); err != nil {
		lg.Error(err, "failed to list nodes for stale check")
		return
	}

	now := time.Now()
	for _, n := range nodes.Items {
		notReadySince := getNodeNotReadyDuration(&n)
		if notReadySince == nil {
			continue
		}

		notReadyFor := now.Sub(*notReadySince)
		if notReadyFor < c.config.MaxNodeStaleDuration {
			continue
		}

		ident := n.Name

		c.queueMu.RLock()
		_, inQueue := c.queue[ident]
		c.queueMu.RUnlock()
		if inQueue {
			continue
		}

		lg.Info("node has been NotReady for too long, triggering cleanup",
			"node", n.Name, "ident", ident,
			"notReadySince", notReadySince, "duration", notReadyFor,
		)
		c.tagAndQueue(ctx, ident, n.Name, now)
	}
}

// getNodeNotReadyDuration returns the time when the node first entered a
// non-Ready state (False or Unknown), or nil if the node is Ready.
func getNodeNotReadyDuration(node *corev1.Node) *time.Time {
	for _, cond := range node.Status.Conditions {
		if cond.Type == corev1.NodeReady {
			if cond.Status != corev1.ConditionTrue {
				return &cond.LastTransitionTime.Time
			}
			return nil
		}
	}
	return nil
}

// ---- periodic cleanup ----

func (c *Controller) processCleanups(ctx context.Context) {
	lg := log.FromContext(ctx)
	now := time.Now()

	c.queueMu.RLock()
	items := make([]*PendingItem, 0, len(c.queue))
	for _, item := range c.queue {
		items = append(items, item)
	}
	c.queueMu.RUnlock()

	for _, item := range items {
		if now.Before(item.DeletedAt.Add(item.WaitDuration)) {
			continue
		}

		if err := c.verifyAndDelete(ctx, item); err != nil {
			lg.Error(err, "cleanup failed", "ident", item.Ident)
			continue
		}

		c.queueMu.Lock()
		delete(c.queue, item.Ident)
		c.queueMu.Unlock()
		lg.Info("cleanup completed", "ident", item.Ident)
	}
}

func (c *Controller) verifyAndDelete(ctx context.Context, item *PendingItem) error {
	lg := log.FromContext(ctx)
	clusterTag := fmt.Sprintf("cluster=%s", c.config.ClusterName)
	filterTags := []string{clusterTag}

	// 1. Check heartbeat has stopped.
	stopped, err := c.fc.CheckHeartbeatStopped(item.Ident, filterTags, c.config.HeartbeatInterval, c.config.HeartbeatStopFactor)
	if err != nil {
		return fmt.Errorf("heartbeat check: %w", err)
	}
	if !stopped {
		return fmt.Errorf("heartbeat still active, deferring")
	}

	// 2. Safety — ident uniqueness: list ALL targets with this ident and cluster tag.
	// If multiple exist and any still has active heartbeat, abort —
	// DeleteTarget removes ALL devices sharing the same ident.
	targets, err := c.fc.ListTargetsByIdent(item.Ident, filterTags)
	if err != nil {
		lg.Error(err, "uniqueness check failed, proceeding with caution", "ident", item.Ident)
	} else if len(targets) > 1 {
		threshold := time.Now().UnixMilli() - int64(c.config.HeartbeatInterval.Milliseconds())*int64(c.config.HeartbeatStopFactor)
		active := 0
		for _, t := range targets {
			if t.TargetUp != 0 && t.Unixtime >= threshold {
				active++
			}
		}
		if active > 0 {
			return fmt.Errorf("ident %s has %d targets with active heartbeat (%d total), aborting deletion",
				item.Ident, active, len(targets))
		}
	}

	// 3. Delete the device.
	if err := c.fc.DeleteTarget(item.Ident); err != nil {
		return fmt.Errorf("delete target: %w", err)
	}

	// 4. Verify the deletion actually took effect — the Flashcat list API can
	// be eventually consistent, so treat "still present" as a retryable failure
	// instead of logging a false "cleanup completed".
	if t, err := c.fc.GetTargetByIdent(item.Ident, nil); err == nil && t != nil {
		return fmt.Errorf("target %s still present after delete, will retry", item.Ident)
	}

	// 设备删除后其标签随之消失，无需再单独清理 gone 标签。
	return nil
}

// ---- startup recovery ----

func (c *Controller) recoverFromFlashcat(ctx context.Context) {
	lg := log.FromContext(ctx)

	targets, err := c.fc.ListTargetsWithTags([]string{
		c.config.TagGoneKey + "=true",
	})
	if err != nil {
		lg.Error(err, "recovery scan failed")
		return
	}

	c.queueMu.Lock()
	defer c.queueMu.Unlock()

	for _, t := range targets {
		if _, ok := c.queue[t.Ident]; ok {
			continue
		}

		// 跳过不属于当前 cluster 的设备（通过 tags_maps 判断）
		if t.TagsMaps != nil && t.TagsMaps["cluster"] != c.config.ClusterName {
			continue
		}

		// 跳过非 Node Agent 的设备（如 ksmAgent）
		if t.TagsMaps != nil && t.TagsMaps["categraf"] != "nodeAgent" {
			continue
		}

		deletedAt := findDeletedAt(t.Tags, c.config.TagDeletedAtKey)
		c.queue[t.Ident] = &PendingItem{
			Ident:        t.Ident,
			DeletedAt:    deletedAt,
			WaitDuration: c.config.DefaultWaitDuration,
		}
		lg.Info("recovered pending item from Flashcat", "ident", t.Ident, "deletedAt", deletedAt)
	}
}

// reconcileMissingNodes 全量扫描：找出 Flashcat 中有但 K8s 中已不存在的设备，
// 补打 gone 标签。这消除了 "operator 所在节点下线" 的竞态。
func (c *Controller) reconcileMissingNodes(ctx context.Context) {
	lg := log.FromContext(ctx)

	// 1. 获取所有 K8s Node 名称集合。
	var nodes corev1.NodeList
	if err := c.client.List(ctx, &nodes); err != nil {
		lg.Error(err, "failed to list nodes for reconciliation")
		return
	}
	k8sIdents := make(map[string]struct{}, len(nodes.Items))
	for _, n := range nodes.Items {
		k8sIdents[n.Name] = struct{}{}
	}

	// 2. 获取 Flashcat 中所有该 cluster 的设备。
	allTargets, err := c.fc.ListTargetsByCluster(c.config.ClusterName)
	if err != nil {
		lg.Error(err, "failed to list Flashcat targets for reconciliation")
		return
	}

	// 3. 找出 Flashcat 中有但 K8s 中没有的，且还没被标记 gone 的。
	now := time.Now()
	for _, t := range allTargets {
		// 跳过非 Node Agent 的设备（如 ksmAgent）
		if t.TagsMaps != nil && t.TagsMaps["categraf"] != "nodeAgent" {
			continue
		}

		if _, ok := k8sIdents[t.Ident]; ok {
			continue // Node 还存在，跳过
		}

		c.queueMu.RLock()
		_, inQueue := c.queue[t.Ident]
		c.queueMu.RUnlock()
		if inQueue {
			continue // 已经在队列里了
		}

		// 检查是否已经被标记 gone
		if hasTag(t.Tags, c.config.TagGoneKey+"=true") {
			// 已经被标记但可能还没恢复进队列，这里恢复一下
			deletedAt := findDeletedAt(t.Tags, c.config.TagDeletedAtKey)
			c.queueMu.Lock()
			c.queue[t.Ident] = &PendingItem{
				Ident:        t.Ident,
				DeletedAt:    deletedAt,
				WaitDuration: c.config.DefaultWaitDuration,
			}
			c.queueMu.Unlock()
			lg.Info("reconciled missing node (already tagged)", "ident", t.Ident, "deletedAt", deletedAt)
			continue
		}

		// 补打 gone 标签
		lg.Info("reconciled missing node (newly found)", "ident", t.Ident)
		c.tagAndQueue(ctx, t.Ident, t.Ident, now)
	}
}

func findDeletedAt(tags []string, key string) time.Time {
	prefix := key + "="
	for _, tag := range tags {
		if strings.HasPrefix(tag, prefix) {
			val := strings.TrimPrefix(tag, prefix)
			var millis int64
			if _, err := fmt.Sscanf(val, "%d", &millis); err == nil {
				return time.UnixMilli(millis)
			}
		}
	}
	return time.Now()
}

func hasTag(tags []string, target string) bool {
	for _, t := range tags {
		if t == target {
			return true
		}
	}
	return false
}

// isDuplicateTagKeyErr reports whether a Flashcat tagging error is the
// benign "duplicate tagkey" case — the target already carries the tag.
func isDuplicateTagKeyErr(err error) bool {
	return err != nil && strings.Contains(err.Error(), "duplicate tagkey")
}
