package controller

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/flashcat/categraf-operator/internal/config"
	"github.com/flashcat/categraf-operator/internal/flashcat"
)

func fakeClient() *fake.ClientBuilder {
	return fake.NewClientBuilder()
}

func node(name string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
	}
}

func tagOK(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"dat": map[string]interface{}{}, "err": ""})
}

func TestFindDeletedAt_ParsesMillis(t *testing.T) {
	tags := []string{
		"categraf_node_gone=true",
		"categraf_node_deleted_at=1700000000000",
	}
	got := findDeletedAt(tags, "categraf_node_deleted_at")
	want := time.UnixMilli(1700000000000)
	if !got.Equal(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestFindDeletedAt_DefaultsToNow(t *testing.T) {
	tags := []string{"categraf_node_gone=true"}
	got := findDeletedAt(tags, "categraf_node_deleted_at")
	if got.IsZero() || got.After(time.Now()) {
		t.Fatalf("expected a recent time, got %v", got)
	}
}

func TestOnNodeDeleted_TagsAndQueues(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tagOK(w)
	}))
	defer srv.Close()

	cfg := &config.Config{
		FlashcatAddr:        srv.URL,
		ClusterName:         "test-cluster",
		TagGoneKey:          "categraf_node_gone",
		TagDeletedAtKey:     "categraf_node_deleted_at",
		DefaultWaitDuration: 24 * time.Hour,
		ReconcileInterval:   5 * time.Minute,
	}
	fc := flashcat.NewClient(cfg.FlashcatAddr, "tok", 5*time.Second)
	c := New(fakeClient().Build(), cfg, fc)

	c.OnNodeDeleted(node("test-node"))

	c.queueMu.RLock()
	item, ok := c.queue["test-node"]
	c.queueMu.RUnlock()

	if !ok {
		t.Fatal("expected item in queue")
	}
	if item.Ident != "test-node" {
		t.Fatalf("expected ident test-node, got %s", item.Ident)
	}
	if item.NodeName != "test-node" {
		t.Fatalf("expected node name test-node, got %s", item.NodeName)
	}
}

func TestProcessCleanups_RemovesExpiredItems(t *testing.T) {
	deleted := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method == "DELETE" {
			deleted = true
			json.NewEncoder(w).Encode(map[string]interface{}{"err": ""})
			return
		}
		list := []map[string]interface{}{}
		if !deleted {
			list = append(list, map[string]interface{}{
				"id":        1,
				"ident":     "gone-device",
				"target_up": 0,
				"unixtime":  1000,
				"tags":      []string{"categraf_node_gone=true", "cluster=test-cluster"},
			})
		}
		resp := map[string]interface{}{
			"dat": map[string]interface{}{
				"list":  list,
				"total": len(list),
			},
			"err": "",
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	cfg := &config.Config{
		FlashcatAddr:        srv.URL,
		ClusterName:         "test-cluster",
		TagGoneKey:          "categraf_node_gone",
		TagDeletedAtKey:     "categraf_node_deleted_at",
		DefaultWaitDuration: 1 * time.Nanosecond,
		HeartbeatInterval:   10 * time.Second,
		HeartbeatStopFactor: 3,
		ReconcileInterval:   5 * time.Minute,
	}
	fc := flashcat.NewClient(cfg.FlashcatAddr, "tok", 5*time.Second)
	ctrl := New(fakeClient().Build(), cfg, fc)

	ctrl.queueMu.Lock()
	ctrl.queue["gone-device"] = &PendingItem{
		Ident:        "gone-device",
		DeletedAt:    time.Now().Add(-2 * time.Hour),
		WaitDuration: 1 * time.Nanosecond,
	}
	ctrl.queueMu.Unlock()

	ctrl.processCleanups(context.Background())

	ctrl.queueMu.RLock()
	_, stillThere := ctrl.queue["gone-device"]
	ctrl.queueMu.RUnlock()

	if stillThere {
		t.Fatal("expected item to be removed after cleanup")
	}
}

func TestRecoverFromFlashcat(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		resp := map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{
						"id":        1,
						"ident":     "recovered-device",
						"target_up": 0,
						"unixtime":  1000,
						"tags":      []string{"categraf_node_gone=true", "categraf_node_deleted_at=1700000000000", "cluster=test-cluster"},
					},
				},
				"total": 1,
			},
			"err": "",
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	cfg := &config.Config{
		FlashcatAddr:        srv.URL,
		ClusterName:         "test-cluster",
		TagGoneKey:          "categraf_node_gone",
		TagDeletedAtKey:     "categraf_node_deleted_at",
		DefaultWaitDuration: 24 * time.Hour,
		ReconcileInterval:   5 * time.Minute,
	}
	fc := flashcat.NewClient(cfg.FlashcatAddr, "tok", 5*time.Second)
	ctrl := New(fakeClient().Build(), cfg, fc)

	ctrl.recoverFromFlashcat(context.Background())

	ctrl.queueMu.RLock()
	item, ok := ctrl.queue["recovered-device"]
	ctrl.queueMu.RUnlock()

	if !ok {
		t.Fatal("expected recovered-device in queue")
	}
	if item.DeletedAt.UnixMilli() != 1700000000000 {
		t.Fatalf("expected DeletedAt 1700000000000, got %d", item.DeletedAt.UnixMilli())
	}
}

func TestGetNodeNotReadyDuration_ReturnsNilWhenReady(t *testing.T) {
	n := &corev1.Node{
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{
				{Type: corev1.NodeReady, Status: corev1.ConditionTrue},
			},
		},
	}
	if got := getNodeNotReadyDuration(n); got != nil {
		t.Fatalf("expected nil for ready node, got %v", got)
	}
}

func TestGetNodeNotReadyDuration_ReturnsTimeWhenNotReady(t *testing.T) {
	ts := metav1.NewTime(time.Now().Add(-48 * time.Hour))
	n := &corev1.Node{
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{
				{Type: corev1.NodeReady, Status: corev1.ConditionFalse, LastTransitionTime: ts},
			},
		},
	}
	got := getNodeNotReadyDuration(n)
	if got == nil {
		t.Fatal("expected non-nil for NotReady node")
	}
	if !got.Equal(ts.Time) {
		t.Fatalf("expected %v, got %v", ts.Time, got)
	}
}

func TestGetNodeNotReadyDuration_ReturnsTimeWhenUnknown(t *testing.T) {
	ts := metav1.NewTime(time.Now().Add(-24 * time.Hour))
	n := &corev1.Node{
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{
				{Type: corev1.NodeReady, Status: corev1.ConditionUnknown, LastTransitionTime: ts},
			},
		},
	}
	got := getNodeNotReadyDuration(n)
	if got == nil {
		t.Fatal("expected non-nil for Unknown node")
	}
	if !got.Equal(ts.Time) {
		t.Fatalf("expected %v, got %v", ts.Time, got)
	}
}

func TestReconcileMissingNodes(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/api/n9e/targets" {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"dat": map[string]interface{}{
					"list": []map[string]interface{}{
						{
							"id":        1,
							"ident":     "missing-node",
							"target_up": 2,
							"unixtime":  1000,
							"tags":      []string{"cluster=test-cluster"},
							"tags_maps": map[string]string{"cluster": "test-cluster", "categraf": "nodeAgent"},
						},
						{
							"id":        2,
							"ident":     "existing-node",
							"target_up": 2,
							"unixtime":  1000,
							"tags":      []string{"cluster=test-cluster"},
							"tags_maps": map[string]string{"cluster": "test-cluster", "categraf": "nodeAgent"},
						},
					},
					"total": 2,
				},
				"err": "",
			})
			return
		}
		if r.URL.Path == "/api/n9e/targets/tags" {
			tagOK(w)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	cfg := &config.Config{
		FlashcatAddr:        srv.URL,
		ClusterName:         "test-cluster",
		TagGoneKey:          "categraf_node_gone",
		TagDeletedAtKey:     "categraf_node_deleted_at",
		DefaultWaitDuration: 24 * time.Hour,
		ReconcileInterval:   5 * time.Minute,
	}
	fc := flashcat.NewClient(cfg.FlashcatAddr, "tok", 5*time.Second)

	cl := fake.NewClientBuilder().WithObjects(node("existing-node")).Build()
	ctrl := New(cl, cfg, fc)

	ctx := context.Background()
	ctrl.reconcileMissingNodes(ctx)

	ctrl.queueMu.RLock()
	_, missingInQueue := ctrl.queue["missing-node"]
	_, existingInQueue := ctrl.queue["existing-node"]
	ctrl.queueMu.RUnlock()

	if !missingInQueue {
		t.Fatal("expected missing-node to be queued")
	}
	if existingInQueue {
		t.Fatal("expected existing-node NOT to be queued")
	}
}
