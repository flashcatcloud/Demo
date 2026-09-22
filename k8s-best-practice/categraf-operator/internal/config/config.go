package config

import (
	"os"
	"strconv"
	"time"
)

// DefaultClusterName is the built-in default for CLUSTER_NAME. It is safe when
// each cluster reports to its own Flashcat server; when multiple clusters share
// one Flashcat server it must be overridden to a globally unique value, or
// uninstall cleanup may delete other clusters' devices.
const DefaultClusterName = "Kubernetes-cluster"

// Config holds all configuration for the categraf-operator.
type Config struct {
	// Flashcat server address (e.g. "http://192.168.31.14:19000").
	FlashcatAddr string

	// X-User-Token header value.
	FlashcatUserToken string

	// Default wait period between tagging the device as offline and
	// actually deleting it.
	DefaultWaitDuration time.Duration

	// Categraf heartbeat interval (to decide when heartbeat is stale).
	HeartbeatInterval time.Duration

	// Heartbeat stop multiplier:  now - lastHeartbeat >
	// HeartbeatInterval * HeartbeatStopFactor  ⇒  considered stopped.
	HeartbeatStopFactor int

	// Cluster name, prepended to node name for ident: "${CLUSTER_NAME}-${node}".
	ClusterName string

	// Kubernetes namespace where the operator runs.
	Namespace string

	// How often the controller scans pending devices.
	ReconcileInterval time.Duration

	// Tag key added to the Flashcat device when the node is deleted.
	TagGoneKey string

	// Tag key storing the deletion timestamp (epoch millis).
	TagDeletedAtKey string

	// MaxNodeStaleDuration: if > 0, nodes that have been NotReady or Unknown
	// for longer than this duration are treated as deleted and cleaned up.
	// Set to 0 (default) to disable this feature.
	MaxNodeStaleDuration time.Duration

	// CleanupNodeCategraf: when true, the operator deletes Flashcat
	// nodeAgent (DaemonSet) categraf targets for this cluster when the
	// categraf DaemonSet is deleted.
	CleanupNodeCategraf bool

	// CleanupKsmCategraf: when true, the operator deletes Flashcat
	// ksmAgent (StatefulSet) categraf targets for this cluster when the
	// categraf DaemonSet is deleted.
	CleanupKsmCategraf bool

	// CategrafDaemonSetName is the name of the nodeAgent DaemonSet to watch
	// and to stop during uninstall cleanup.
	CategrafDaemonSetName string

	// CategrafKsmStatefulSetName is the name of the ksmAgent StatefulSet to
	// stop during uninstall cleanup.
	CategrafKsmStatefulSetName string

	// CleanupHeartbeatTimeout bounds how long uninstall cleanup waits for
	// device heartbeats to stop before deleting them.
	CleanupHeartbeatTimeout time.Duration

	// CategrafOperatorDeploymentName is the operator's own Deployment. During
	// cleanup-once the hook stops it first so its informer fallback cannot race
	// the hook on the same Flashcat deletions.
	CategrafOperatorDeploymentName string
}

// Default returns a Config populated from environment variables.
func Default() *Config {
	return &Config{
		FlashcatAddr:                   getEnv("FLASHCAT_ADDR", "http://127.0.0.1:19000"),
		FlashcatUserToken:              getEnv("FLASHCAT_USER_TOKEN", ""),
		DefaultWaitDuration:            getDurationEnv("DEFAULT_WAIT_DURATION", 1*time.Hour),
		HeartbeatInterval:              getDurationEnv("HEARTBEAT_INTERVAL", 10*time.Second),
		HeartbeatStopFactor:            getIntEnv("HEARTBEAT_STOP_FACTOR", 3),
		ClusterName:                    getEnv("CLUSTER_NAME", DefaultClusterName),
		Namespace:                      getEnv("NAMESPACE", "flashcat"),
		ReconcileInterval:              getDurationEnv("RECONCILE_INTERVAL", 5*time.Minute),
		TagGoneKey:                     "categraf_node_gone",
		TagDeletedAtKey:                "categraf_node_deleted_at",
		MaxNodeStaleDuration:           getDurationEnv("MAX_NODE_STALE_DURATION", 0),
		CleanupNodeCategraf:            getBoolEnv("CLEANUP_NODE_CATEGRAF", false),
		CleanupKsmCategraf:             getBoolEnv("CLEANUP_KSM_CATEGRAF", false),
		CategrafDaemonSetName:          getEnv("CATEGRAF_DAEMONSET_NAME", "categraf"),
		CategrafKsmStatefulSetName:     getEnv("CATEGRAF_KSM_STATEFULSET_NAME", "categraf-ksm"),
		CleanupHeartbeatTimeout:        getDurationEnv("CLEANUP_HEARTBEAT_TIMEOUT", 2*time.Minute),
		CategrafOperatorDeploymentName: getEnv("CATEGRAF_OPERATOR_DEPLOYMENT_NAME", "categraf-operator"),
	}
}

func getEnv(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}

func getDurationEnv(key string, defaultVal time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return defaultVal
}

func getIntEnv(key string, defaultVal int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return defaultVal
}

func getBoolEnv(key string, defaultVal bool) bool {
	if v := os.Getenv(key); v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			return b
		}
	}
	return defaultVal
}
