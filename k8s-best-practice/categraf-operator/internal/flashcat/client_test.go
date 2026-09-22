package flashcat

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestGetTargetByIdent(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Fatalf("expected GET, got %s", r.Method)
		}
		if r.URL.Query().Get("hosts") != "test-ident" {
			t.Fatalf("expected hosts=test-ident, got %s", r.URL.RawQuery)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{
						"id":        1,
						"ident":     "test-ident",
						"unixtime":  1700000000000,
						"target_up": 2,
						"tags":      []string{"a=b"},
					},
				},
				"total": 1,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	target, err := c.GetTargetByIdent("test-ident", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if target.Ident != "test-ident" {
		t.Fatalf("expected ident test-ident, got %s", target.Ident)
	}
	if target.TargetUp != 2 {
		t.Fatalf("expected target_up=2, got %d", target.TargetUp)
	}
	if len(target.Tags) != 1 || target.Tags[0] != "a=b" {
		t.Fatalf("unexpected tags: %v", target.Tags)
	}
}

func TestGetTargetByIdent_WithTagFilter(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{
						"id":        1,
						"ident":     "test-ident",
						"unixtime":  1700000000000,
						"target_up": 2,
						"tags":      []string{"cluster=other-cluster"},
					},
					{
						"id":        2,
						"ident":     "test-ident",
						"unixtime":  1700000000000,
						"target_up": 2,
						"tags":      []string{"cluster=test-cluster"},
					},
				},
				"total": 2,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	target, err := c.GetTargetByIdent("test-ident", []string{"cluster=test-cluster"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if target.ID != 2 {
		t.Fatalf("expected target id=2 (cluster match), got %d", target.ID)
	}
}

func TestGetTargetByIdent_NotFound(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list":  []map[string]interface{}{},
				"total": 0,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	_, err := c.GetTargetByIdent("nonexistent", nil)
	if err == nil {
		t.Fatal("expected error for nonexistent target")
	}
}

func TestTagTarget(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/api/n9e/targets/tags" {
			t.Fatalf("expected /api/n9e/targets/tags, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	if err := c.TagTarget("test-ident", []string{"key=value"}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestTagTarget_ReturnsErrorOnDatFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"test-ident": "duplicate tagkey(cluster)",
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	err := c.TagTarget("test-ident", []string{"cluster=test"})
	if err == nil {
		t.Fatal("expected error for duplicate tagkey")
	}
	if !strings.Contains(err.Error(), "duplicate tagkey") {
		t.Fatalf("expected duplicate tagkey error, got: %v", err)
	}
}

func TestDeleteTarget(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "DELETE" {
			t.Fatalf("expected DELETE, got %s", r.Method)
		}
		if r.URL.Path != "/api/n9e/targets" {
			t.Fatalf("expected /api/n9e/targets, got %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	if err := c.DeleteTarget("test-ident"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestCheckHeartbeatStopped_ReturnsTrueWhenDown(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{"id": 1, "ident": "down-device", "target_up": 0, "unixtime": 1000},
				},
				"total": 1,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	stopped, err := c.CheckHeartbeatStopped("down-device", nil, 10*time.Second, 3)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !stopped {
		t.Fatal("expected stopped=true for target_up=0")
	}
}

func TestCheckHeartbeatStopped_ReturnsFalseWhenRecent(t *testing.T) {
	now := time.Now().UnixMilli()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{"id": 1, "ident": "live-device", "target_up": 2, "unixtime": now},
				},
				"total": 1,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	stopped, err := c.CheckHeartbeatStopped("live-device", nil, 10*time.Second, 3)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if stopped {
		t.Fatal("expected stopped=false for recently heartbeating device")
	}
}

func TestListTargets(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Fatalf("expected GET, got %s", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{"id": 1, "ident": "dev-1", "target_up": 2, "unixtime": 1000, "tags": []string{"a=b"}},
					{"id": 2, "ident": "dev-2", "target_up": 0, "unixtime": 500, "tags": []string{"c=d"}},
				},
				"total": 2,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	targets, total, err := c.ListTargets(100, 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if total != 2 {
		t.Fatalf("expected total=2, got %d", total)
	}
	if len(targets) != 2 {
		t.Fatalf("expected 2 targets, got %d", len(targets))
	}
	if targets[0].Ident != "dev-1" {
		t.Fatalf("expected dev-1, got %s", targets[0].Ident)
	}
}

func TestListTargetsWithTag(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{
						"id":        1,
						"ident":     "tagged-dev",
						"target_up": 0,
						"unixtime":  1000,
						"tags":      []string{"env=prod", "categraf_node_gone=true"},
					},
					{
						"id":        2,
						"ident":     "normal-dev",
						"target_up": 2,
						"unixtime":  2000,
						"tags":      []string{"env=prod"},
					},
				},
				"total": 2,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	matched, err := c.ListTargetsWithTag("categraf_node_gone=true")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(matched) != 1 {
		t.Fatalf("expected 1 matched target, got %d", len(matched))
	}
	if matched[0].Ident != "tagged-dev" {
		t.Fatalf("expected tagged-dev, got %s", matched[0].Ident)
	}
}

func TestListTargetsWithTags(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{
						"id":        1,
						"ident":     "dev-1",
						"target_up": 0,
						"unixtime":  1000,
						"tags":      []string{"cluster=a", "categraf_node_gone=true"},
					},
					{
						"id":        2,
						"ident":     "dev-2",
						"target_up": 0,
						"unixtime":  1000,
						"tags":      []string{"cluster=b", "categraf_node_gone=true"},
					},
					{
						"id":        3,
						"ident":     "dev-3",
						"target_up": 2,
						"unixtime":  2000,
						"tags":      []string{"cluster=a"},
					},
				},
				"total": 3,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	matched, err := c.ListTargetsWithTags([]string{"cluster=a", "categraf_node_gone=true"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(matched) != 1 {
		t.Fatalf("expected 1 matched target, got %d", len(matched))
	}
	if matched[0].Ident != "dev-1" {
		t.Fatalf("expected dev-1, got %s", matched[0].Ident)
	}
}

func TestHasTag(t *testing.T) {
	tags := []string{"a=b", "categraf_node_gone=true", "env=prod"}
	if !hasTag(tags, "categraf_node_gone=true") {
		t.Fatal("expected hasTag to return true for existing tag")
	}
	if hasTag(tags, "nonexistent") {
		t.Fatal("expected hasTag to return false for missing tag")
	}
}

func TestHasAllTags(t *testing.T) {
	tags := []string{"a=b", "categraf_node_gone=true", "env=prod"}
	if !hasAllTags(tags, []string{"a=b", "env=prod"}) {
		t.Fatal("expected hasAllTags to return true when all tags present")
	}
	if hasAllTags(tags, []string{"a=b", "missing=true"}) {
		t.Fatal("expected hasAllTags to return false when a tag is missing")
	}
	if !hasAllTags(tags, nil) {
		t.Fatal("expected hasAllTags to return true for nil filter")
	}
}

func TestListTargetsByIdent(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{"id": 1, "ident": "dup-ident", "target_up": 2, "unixtime": time.Now().UnixMilli(), "tags": []string{}},
					{"id": 2, "ident": "dup-ident", "target_up": 0, "unixtime": 1000, "tags": []string{}},
				},
				"total": 2,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	targets, err := c.ListTargetsByIdent("dup-ident", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(targets) != 2 {
		t.Fatalf("expected 2 targets, got %d", len(targets))
	}
}

func TestListTargetsByIdent_WithTagFilter(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{"id": 1, "ident": "dup-ident", "target_up": 2, "unixtime": time.Now().UnixMilli(), "tags": []string{"cluster=a"}},
					{"id": 2, "ident": "dup-ident", "target_up": 0, "unixtime": 1000, "tags": []string{"cluster=b"}},
				},
				"total": 2,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	targets, err := c.ListTargetsByIdent("dup-ident", []string{"cluster=b"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(targets) != 1 {
		t.Fatalf("expected 1 target after tag filter, got %d", len(targets))
	}
	if targets[0].ID != 2 {
		t.Fatalf("expected target id=2, got %d", targets[0].ID)
	}
}

func TestListTargetsByCluster(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"dat": map[string]interface{}{
				"list": []map[string]interface{}{
					{
						"id":        1,
						"ident":     "dev-a",
						"target_up": 2,
						"unixtime":  1000,
						"tags":      []string{"cluster=test-cluster"},
						"tags_maps": map[string]string{"cluster": "test-cluster"},
					},
					{
						"id":        2,
						"ident":     "dev-b",
						"target_up": 2,
						"unixtime":  1000,
						"tags":      []string{"cluster=other-cluster"},
						"tags_maps": map[string]string{"cluster": "other-cluster"},
					},
				},
				"total": 2,
			},
			"err": "",
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok", 5*time.Second)
	matched, err := c.ListTargetsByCluster("test-cluster")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(matched) != 1 {
		t.Fatalf("expected 1 matched target, got %d", len(matched))
	}
	if matched[0].Ident != "dev-a" {
		t.Fatalf("expected dev-a, got %s", matched[0].Ident)
	}
}
