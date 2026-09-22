package controller

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/flashcat/categraf-operator/internal/config"
	"github.com/flashcat/categraf-operator/internal/flashcat"
)

// TestRunCleanupOnce_DeletesClusterTargetsOnly covers the pre-delete hook flow
// (--cleanup-once):
//   - nodeAgent/ksmAgent workloads are deleted,
//   - targets of THIS cluster are deleted only after heartbeat stop,
//   - business group APIs are never called,
//   - devices of other clusters are never touched.
func TestRunCleanupOnce_DeletesClusterTargetsOnly(t *testing.T) {
	var mu sync.Mutex
	targets := []flashcat.Target{
		{ID: 1, Ident: "test-cluster-node1", TargetUp: 0, Unixtime: 1000,
			TagsMaps: map[string]string{"cluster": "test-cluster", "categraf": "nodeAgent"}},
		{ID: 2, Ident: "test-cluster-ksm-0", TargetUp: 0, Unixtime: 1000,
			TagsMaps: map[string]string{"cluster": "test-cluster", "categraf": "ksmAgent"}},
		// Another cluster's device must be kept.
		{ID: 3, Ident: "other-cluster-node1", TargetUp: 2, Unixtime: time.Now().UnixMilli(),
			TagsMaps: map[string]string{"cluster": "other-cluster", "categraf": "nodeAgent"}},
	}
	var deletedIdents []string
	businessGroupAccessed := false

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		mu.Lock()
		defer mu.Unlock()

		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/api/n9e/targets":
			if hosts := r.URL.Query().Get("hosts"); hosts != "" {
				var list []flashcat.Target
				for _, t := range targets {
					if t.Ident == hosts {
						list = append(list, t)
					}
				}
				json.NewEncoder(w).Encode(map[string]interface{}{
					"dat": map[string]interface{}{"list": list, "total": len(list)}, "err": "",
				})
				return
			}
			json.NewEncoder(w).Encode(map[string]interface{}{
				"dat": map[string]interface{}{"list": targets, "total": len(targets)}, "err": "",
			})

		case r.Method == http.MethodDelete && r.URL.Path == "/api/n9e/targets":
			var body struct {
				Idents []string `json:"idents"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			remove := make(map[string]bool, len(body.Idents))
			for _, id := range body.Idents {
				remove[id] = true
			}
			kept := targets[:0]
			for _, t := range targets {
				if !remove[t.Ident] {
					kept = append(kept, t)
				}
			}
			targets = kept
			deletedIdents = append(deletedIdents, body.Idents...)
			json.NewEncoder(w).Encode(map[string]interface{}{"err": ""})

		default:
			if r.URL.Path == "/api/n9e/busi-groups" || strings.HasPrefix(r.URL.Path, "/api/n9e/busi-group/") {
				businessGroupAccessed = true
			}
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	cfg := &config.Config{
		FlashcatAddr:               srv.URL,
		ClusterName:                "test-cluster",
		Namespace:                  "categraf",
		HeartbeatInterval:          10 * time.Second,
		HeartbeatStopFactor:        3,
		CleanupHeartbeatTimeout:    2 * time.Second,
		CleanupNodeCategraf:        true,
		CleanupKsmCategraf:         true,
		CategrafDaemonSetName:      "categraf",
		CategrafKsmStatefulSetName: "categraf-ksm",
	}
	fc := flashcat.NewClient(cfg.FlashcatAddr, "tok", 5*time.Second)

	ds := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: "categraf", Namespace: "categraf"}}
	ss := &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: "categraf-ksm", Namespace: "categraf"}}
	cl := fake.NewClientBuilder().WithScheme(clientgoscheme.Scheme).WithObjects(ds, ss).Build()

	c := New(cl, cfg, fc)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := c.RunCleanupOnce(ctx); err != nil {
		t.Fatalf("RunCleanupOnce returned error: %v", err)
	}

	// Workloads deleted.
	var gotDS appsv1.DaemonSet
	if err := cl.Get(ctx, types.NamespacedName{Name: "categraf", Namespace: "categraf"}, &gotDS); err == nil {
		t.Fatal("expected DaemonSet to be deleted")
	}
	var gotSS appsv1.StatefulSet
	if err := cl.Get(ctx, types.NamespacedName{Name: "categraf-ksm", Namespace: "categraf"}, &gotSS); err == nil {
		t.Fatal("expected StatefulSet to be deleted")
	}

	mu.Lock()
	defer mu.Unlock()
	if !contains(deletedIdents, "test-cluster-node1") || !contains(deletedIdents, "test-cluster-ksm-0") {
		t.Fatalf("expected cluster targets deleted, got %v", deletedIdents)
	}
	if contains(deletedIdents, "other-cluster-node1") {
		t.Fatalf("other cluster's device must not be deleted: %v", deletedIdents)
	}
	if businessGroupAccessed {
		t.Fatal("business group API must not be accessed")
	}
}

func contains(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}
