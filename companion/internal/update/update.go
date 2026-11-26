// Package update is the optional self-update from GitHub Releases. It is OFF by default
// (config "self_update"); when off, NAVTOK never contacts anything but the webhook.
package update

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// AssetName is the release asset that is downloaded for this OS.
var AssetName = func() string {
	if runtime.GOOS == "windows" {
		return "NAVTOK.exe"
	}
	return "navtok-" + runtime.GOOS + "-" + runtime.GOARCH
}()

// Release is the subset of the GitHub API answer we use.
type Release struct {
	Tag    string `json:"tag_name"`
	Assets []struct {
		Name string `json:"name"`
		URL  string `json:"browser_download_url"`
	} `json:"assets"`
}

// APIBase can be overridden in tests.
var APIBase = "https://api.github.com"

// Latest fetches the latest release of repo ("owner/name").
func Latest(ctx context.Context, c *http.Client, repo string) (*Release, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, APIBase+"/repos/"+repo+"/releases/latest", nil)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "NAVTOK-updater")
	resp, err := c.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("update: HTTP %d", resp.StatusCode)
	}
	var r Release
	return &r, json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&r)
}

// Newer reports whether tag (v1.2.3) is newer than current.
func Newer(tag, current string) bool {
	a, b := parse(tag), parse(current)
	for i := 0; i < 3; i++ {
		if a[i] != b[i] {
			return a[i] > b[i]
		}
	}
	return false
}

func parse(v string) [3]int {
	var out [3]int
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	v, _, _ = strings.Cut(v, "-")
	for i, p := range strings.SplitN(v, ".", 3) {
		out[i], _ = strconv.Atoi(p)
	}
	return out
}

// Apply downloads the new exe next to the running one and swaps them (Windows allows renaming a
// running executable). The new version runs on the next start.
func Apply(ctx context.Context, c *http.Client, r *Release) error {
	var url string
	for _, a := range r.Assets {
		if a.Name == AssetName {
			url = a.URL
		}
	}
	if url == "" {
		return errors.New("update: release has no " + AssetName)
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	resp, err := c.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("update: download HTTP %d", resp.StatusCode)
	}
	tmp := exe + ".new"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	n, err := io.Copy(f, io.LimitReader(resp.Body, 100<<20))
	f.Close()
	if err != nil || n < 1<<20 {
		os.Remove(tmp)
		return fmt.Errorf("update: bad download (%d bytes): %v", n, err)
	}
	old := exe + ".old"
	os.Remove(old)
	if err := os.Rename(exe, old); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, exe); err != nil {
		os.Rename(old, exe)
		return err
	}
	return nil
}

// Cleanup removes the .old exe left by a previous update.
func Cleanup() {
	if exe, err := os.Executable(); err == nil {
		os.Remove(exe + ".old")
		os.Remove(filepath.Clean(exe + ".new"))
	}
}

// Check runs Latest+Apply when a newer version exists. Returns the new tag or "".
func Check(ctx context.Context, repo, current string) (string, error) {
	c := &http.Client{Timeout: 2 * time.Minute}
	r, err := Latest(ctx, c, repo)
	if err != nil {
		return "", err
	}
	if !Newer(r.Tag, current) {
		return "", nil
	}
	return r.Tag, Apply(ctx, c, r)
}
