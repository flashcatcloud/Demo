package flashcat

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client is a lightweight HTTP client for the Flashcat device-management API.
type Client struct {
	baseURL   string // e.g. "http://192.168.31.14:19000/api/n9e"
	userToken string
	http      *http.Client
}

// Target represents a monitored device returned by the Flashcat targets API.
type Target struct {
	ID         int               `json:"id"`
	Ident      string            `json:"ident"`
	Tags       []string          `json:"tags"`
	TagsMaps   map[string]string `json:"tags_maps,omitempty"`
	Unixtime   int64             `json:"unixtime"`  // last heartbeat (ms)
	TargetUp   int               `json:"target_up"` // 0=down, 2=up
	UpdateAt   int64             `json:"update_at"` // last update (unix)
	HostIP     string            `json:"host_ip"`
	RemoteAddr string            `json:"remote_addr"`
}

// ---- internal types ----

type targetListResponse struct {
	Dat struct {
		List  []Target `json:"list"`
		Total int      `json:"total"`
	} `json:"dat"`
	Err string `json:"err"`
}

type apiErrorResponse struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
	RequestID string `json:"request_id"`
}

type tagOpRequest struct {
	Idents []string `json:"idents"`
	Tags   []string `json:"tags"`
}

type tagResponse struct {
	Dat map[string]string `json:"dat"`
	Err string            `json:"err"`
}

type deleteRequest struct {
	Idents []string `json:"idents"`
	Force  bool     `json:"force"`
}

// errResponse captures the n9e-style {"err": "..."} body returned even on
// HTTP 200 when the operation fails server-side.
type errResponse struct {
	Err string `json:"err"`
}

// ---- construction ----

// NewClient creates a new Flashcat API client.
// addr is the full Flashcat server address, e.g. "http://192.168.31.14:19000".
func NewClient(addr, userToken string, timeout time.Duration) *Client {
	return &Client{
		baseURL:   addr + "/api/n9e",
		userToken: userToken,
		http: &http.Client{
			Timeout: timeout,
		},
	}
}

// ---- request helpers ----

func (c *Client) newRequest(method, path string, body interface{}) (*http.Request, error) {
	var r io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("marshal body: %w", err)
		}
		r = bytes.NewReader(b)
	}

	req, err := http.NewRequest(method, c.baseURL+path, r)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if c.userToken != "" {
		req.Header.Set("X-User-Token", c.userToken)
	}

	return req, nil
}

func (c *Client) do(req *http.Request, out interface{}) error {
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("http do: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		var errResp apiErrorResponse
		if decodeErr := json.NewDecoder(resp.Body).Decode(&errResp); decodeErr == nil && errResp.Error.Message != "" {
			return fmt.Errorf("api error [%d]: %s", resp.StatusCode, errResp.Error.Message)
		}
		return fmt.Errorf("http status: %d", resp.StatusCode)
	}

	if out != nil {
		if err := json.NewDecoder(resp.Body).Decode(out); err != nil && err != io.EOF {
			return fmt.Errorf("decode response: %w", err)
		}
	}

	return nil
}

// ---- public API ----

// GetTargetByIdent queries Flashcat for a single target by ident,
// optionally filtering by tags (all must match).
func (c *Client) GetTargetByIdent(ident string, filterTags []string) (*Target, error) {
	q := url.Values{}
	q.Set("hosts", ident)
	req, err := c.newRequest("GET", "/targets?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}

	var resp targetListResponse
	if err := c.do(req, &resp); err != nil {
		return nil, fmt.Errorf("get target %s: %w", ident, err)
	}

	for _, t := range resp.Dat.List {
		if t.Ident == ident && t.HasAllTags(filterTags) {
			return &t, nil
		}
	}
	idents := make([]string, 0, len(resp.Dat.List))
	for _, t := range resp.Dat.List {
		idents = append(idents, fmt.Sprintf("%s(tags=%v tags_maps=%v)", t.Ident, t.Tags, t.TagsMaps))
	}
	return nil, fmt.Errorf("target %s not found (total returned: %d, got: %v)", ident, resp.Dat.Total, idents)
}

// ListTargetsByIdent returns ALL targets matching the given ident,
// optionally filtered by tags (all must match).
func (c *Client) ListTargetsByIdent(ident string, filterTags []string) ([]Target, error) {
	q := url.Values{}
	q.Set("hosts", ident)
	req, err := c.newRequest("GET", "/targets?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	var resp targetListResponse
	if err := c.do(req, &resp); err != nil {
		return nil, fmt.Errorf("list targets by ident: %w", err)
	}

	var matched []Target
	for _, t := range resp.Dat.List {
		if t.Ident == ident && t.HasAllTags(filterTags) {
			matched = append(matched, t)
		}
	}
	return matched, nil
}

// TagTarget adds one or more tags to a target device.
func (c *Client) TagTarget(ident string, tags []string) error {
	req, err := c.newRequest("POST", "/targets/tags", &tagOpRequest{
		Idents: []string{ident},
		Tags:   tags,
	})
	if err != nil {
		return err
	}
	var resp tagResponse
	if err := c.do(req, &resp); err != nil {
		return err
	}
	if resp.Err != "" {
		return fmt.Errorf("flashcat tag error: %s", resp.Err)
	}
	// Flashcat returns HTTP 200 but may put per-ident errors in dat.
	if msg, ok := resp.Dat[ident]; ok && msg != "" {
		return fmt.Errorf("flashcat tag error: %s", msg)
	}
	return nil
}

// DeleteTag removes one or more tags from a target device.
func (c *Client) DeleteTag(ident string, tags []string) error {
	req, err := c.newRequest("DELETE", "/targets/tags", &tagOpRequest{
		Idents: []string{ident},
		Tags:   tags,
	})
	if err != nil {
		return err
	}
	var resp tagResponse
	if err := c.do(req, &resp); err != nil {
		return err
	}
	if resp.Err != "" {
		return fmt.Errorf("flashcat delete-tag error: %s", resp.Err)
	}
	if msg, ok := resp.Dat[ident]; ok && msg != "" {
		return fmt.Errorf("flashcat delete-tag error: %s", msg)
	}
	return nil
}

// DeleteTarget removes a target device from Flashcat.
// force=true is required — without it the server silently skips the deletion
// (returns HTTP 200 with an empty err) when the device still has metadata.
func (c *Client) DeleteTarget(ident string) error {
	req, err := c.newRequest("DELETE", "/targets", &deleteRequest{
		Idents: []string{ident},
		Force:  true,
	})
	if err != nil {
		return err
	}
	// Flashcat/n9e 风格 API 即使失败也返回 HTTP 200，错误在 body 的 err 字段。
	var resp errResponse
	if err := c.do(req, &resp); err != nil {
		return err
	}
	if resp.Err != "" {
		return fmt.Errorf("flashcat delete error: %s", resp.Err)
	}
	return nil
}

// CheckHeartbeatStopped checks whether the device's heartbeat is older than
// heartbeatInterval * factor.  Returns true when the heartbeat is considered
// stopped.  The optional filterTags restrict the search to targets that carry
// all of the supplied tags.
func (c *Client) CheckHeartbeatStopped(ident string, filterTags []string, heartbeatInterval time.Duration, factor int) (bool, error) {
	target, err := c.GetTargetByIdent(ident, filterTags)
	if err != nil {
		return false, err
	}

	if target.TargetUp == 0 {
		return true, nil
	}

	threshold := time.Now().UnixMilli() - int64(heartbeatInterval.Milliseconds())*int64(factor)
	return target.Unixtime < threshold, nil
}

// ListTargets paginates through all targets and returns the results.
func (c *Client) ListTargets(limit, page int) ([]Target, int, error) {
	if limit <= 0 {
		limit = 100
	}
	path := fmt.Sprintf("/targets?limit=%d&p=%d", limit, page)
	req, err := c.newRequest("GET", path, nil)
	if err != nil {
		return nil, 0, err
	}

	var resp targetListResponse
	if err := c.do(req, &resp); err != nil {
		return nil, 0, fmt.Errorf("list targets: %w", err)
	}

	return resp.Dat.List, resp.Dat.Total, nil
}

// ListTargetsWithTag scans all pages of targets and returns those that
// contain the given tag string (exact match, "key=value").
func (c *Client) ListTargetsWithTag(tag string) ([]Target, error) {
	var matched []Target
	page := 1
	limit := 200

	for {
		targets, _, err := c.ListTargets(limit, page)
		if err != nil {
			return nil, err
		}
		for _, t := range targets {
			if hasTag(t.Tags, tag) {
				matched = append(matched, t)
			}
		}
		if len(targets) < limit {
			break
		}
		page++
	}
	return matched, nil
}

// ListTargetsWithTags scans all pages of targets and returns those that
// contain ALL of the supplied tag strings (exact match, "key=value").
func (c *Client) ListTargetsWithTags(tags []string) ([]Target, error) {
	var matched []Target
	page := 1
	limit := 200

	for {
		targets, _, err := c.ListTargets(limit, page)
		if err != nil {
			return nil, err
		}
		for _, t := range targets {
			if t.HasAllTags(tags) {
				matched = append(matched, t)
			}
		}
		if len(targets) < limit {
			break
		}
		page++
	}
	return matched, nil
}

// ListTargetsByCluster paginates through all targets and returns those
// whose tags_maps["cluster"] matches the given cluster name.
func (c *Client) ListTargetsByCluster(cluster string) ([]Target, error) {
	var matched []Target
	page := 1
	limit := 200

	for {
		targets, _, err := c.ListTargets(limit, page)
		if err != nil {
			return nil, err
		}
		for _, t := range targets {
			if t.TagsMaps != nil && t.TagsMaps["cluster"] == cluster {
				matched = append(matched, t)
			}
		}
		if len(targets) < limit {
			break
		}
		page++
	}
	return matched, nil
}

func hasTag(tags []string, target string) bool {
	for _, t := range tags {
		if t == target {
			return true
		}
	}
	return false
}

// HasAllTags reports whether the target carries ALL of the supplied tags
// ("key=value"), checking both the tags list and tags_maps.
func (t *Target) HasAllTags(filterTags []string) bool {
	for _, f := range filterTags {
		if hasTag(t.Tags, f) {
			continue
		}
		// Fall back to tags_maps: filter "k=v" matches tags_maps[k]==v.
		k, v, ok := strings.Cut(f, "=")
		if ok && t.TagsMaps != nil && t.TagsMaps[k] == v {
			continue
		}
		return false
	}
	return true
}

func hasAllTags(tags, targets []string) bool {
	for _, target := range targets {
		if !hasTag(tags, target) {
			return false
		}
	}
	return true
}
