package main

import (
	"context"
	"flag"
	"os"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/client-go/tools/cache"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/flashcat/categraf-operator/internal/config"
	"github.com/flashcat/categraf-operator/internal/controller"
	"github.com/flashcat/categraf-operator/internal/flashcat"
)

var setupLog = ctrl.Log.WithName("setup")

func main() {
	var metricsAddr string
	var probeAddr string
	var enableLeaderElection bool
	var cleanupOnce bool

	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080",
		"The address the metric endpoint binds to.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081",
		"The address the probe endpoint binds to.")
	flag.BoolVar(&enableLeaderElection, "leader-elect", false,
		"Enable leader election for controller manager.")
	flag.BoolVar(&cleanupOnce, "cleanup-once", false,
		"Run a single Flashcat uninstall cleanup and exit (used by the Helm pre-delete hook).")
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseDevMode(true)))

	cfg := config.Default()
	setupLog.Info("configuration loaded",
		"flashcat_addr", cfg.FlashcatAddr,
		"cluster_name", cfg.ClusterName,
		"wait_duration", cfg.DefaultWaitDuration,
		"reconcile_interval", cfg.ReconcileInterval,
		"max_node_stale", cfg.MaxNodeStaleDuration,
	)

	if cfg.FlashcatUserToken == "" {
		setupLog.Info("FLASHCAT_USER_TOKEN is empty, all API calls to Flashcat will fail")
	}

	warnIfDefaultClusterName(cfg)

	if cleanupOnce {
		os.Exit(runCleanupOnce(cfg))
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Metrics: metricsserver.Options{
			BindAddress: metricsAddr,
		},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "categraf-node-cleanup.flashcat.io",
	})
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	// Flashcat API client.
	fc := flashcat.NewClient(cfg.FlashcatAddr, cfg.FlashcatUserToken, 30*time.Second)

	// Create the controller.
	ctrlr := controller.New(mgr.GetClient(), cfg, fc)

	// Register the Node informer from the manager's shared cache so we
	// receive Node deletion events.
	informer, err := mgr.GetCache().GetInformer(context.Background(), &corev1.Node{})
	if err != nil {
		setupLog.Error(err, "unable to get Node informer")
		os.Exit(1)
	}
	informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		DeleteFunc: func(obj interface{}) {
			if node, ok := obj.(*corev1.Node); ok {
				ctrlr.OnNodeDeleted(node)
			}
		},
	})
	setupLog.Info("node informer registered")

	// Watch the categraf DaemonSet for deletion (helm uninstall detection).
	dsInformer, err := mgr.GetCache().GetInformer(context.Background(), &appsv1.DaemonSet{})
	if err != nil {
		setupLog.Error(err, "unable to get DaemonSet informer")
		os.Exit(1)
	}
	dsInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		DeleteFunc: func(obj interface{}) {
			if ds, ok := obj.(*appsv1.DaemonSet); ok {
				ctrlr.OnCategrafDaemonSetDeleted(context.Background(), ds)
			}
		},
	})
	setupLog.Info("daemonset informer registered",
		"watch_name", cfg.CategrafDaemonSetName,
		"cleanup_node_categraf", cfg.CleanupNodeCategraf,
		"cleanup_ksm_categraf", cfg.CleanupKsmCategraf)

	// Register the controller's Run loop as a manager Runnable.
	mgr.Add(manager.RunnableFunc(func(ctx context.Context) error {
		return ctrlr.Run(ctx)
	}))

	// Health probes.
	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up health check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up ready check")
		os.Exit(1)
	}

	setupLog.Info("starting manager")
	if err := mgr.Start(context.Background()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}

// runCleanupOnce performs a single Flashcat uninstall cleanup (used by the Helm
// pre-delete hook via --cleanup-once). It stops the node/ksm workloads, waits
// for heartbeats to stop, deletes targets, then exits.
// Returns a process exit code.
func runCleanupOnce(cfg *config.Config) int {
	setupLog.Info("cleanup-once mode: starting Flashcat uninstall cleanup",
		"flashcat_addr", cfg.FlashcatAddr,
		"cluster_name", cfg.ClusterName)

	fc := flashcat.NewClient(cfg.FlashcatAddr, cfg.FlashcatUserToken, 30*time.Second)

	kc, err := client.New(ctrl.GetConfigOrDie(), client.Options{})
	if err != nil {
		setupLog.Error(err, "unable to create kubernetes client for cleanup-once")
		return 1
	}

	ctrlr := controller.New(kc, cfg, fc)
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Minute)
	defer cancel()

	if err := ctrlr.RunCleanupOnce(ctx); err != nil {
		setupLog.Error(err, "cleanup-once failed")
		return 1
	}
	setupLog.Info("cleanup-once completed successfully")
	return 0
}

// warnIfDefaultClusterName warns when cleanup is enabled but CLUSTER_NAME still
// uses the built-in default. That is safe only when every cluster reports to
// its own Flashcat server; with a shared Flashcat server it can cause uninstall
// cleanup to delete another cluster's devices.
func warnIfDefaultClusterName(cfg *config.Config) {
	if cfg.ClusterName != config.DefaultClusterName {
		return
	}
	if !cfg.CleanupNodeCategraf && !cfg.CleanupKsmCategraf {
		return
	}
	setupLog.Info("WARNING: CLUSTER_NAME uses the default value; if multiple clusters share one Flashcat server, "+
		"set a globally unique CLUSTER_NAME or uninstall cleanup may delete other clusters' devices",
		"cluster_name", cfg.ClusterName)
}
