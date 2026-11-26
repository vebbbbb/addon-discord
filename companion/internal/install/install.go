// Package install copies the embedded addon into Interface\AddOns\NavtokDiscord.
package install

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
)

// AddonName is the addon folder name.
const AddonName = "NavtokDiscord"

type file struct {
	rel  string
	data []byte
}

func files(src fs.FS, root string) ([]file, error) {
	var out []file
	err := fs.WalkDir(src, root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := fs.ReadFile(src, p)
		if err != nil {
			return err
		}
		out = append(out, file{rel: strings.TrimPrefix(p, root+"/"), data: b})
		return nil
	})
	sort.Slice(out, func(i, j int) bool { return out[i].rel < out[j].rel })
	return out, err
}

// Hash identifies the embedded addon build.
func Hash(src fs.FS, root string) (string, error) {
	fl, err := files(src, root)
	if err != nil {
		return "", err
	}
	h := sha256.New()
	for _, f := range fl {
		h.Write([]byte(f.rel))
		h.Write([]byte{0})
		h.Write(f.data)
	}
	return hex.EncodeToString(h.Sum(nil))[:16], nil
}

// Result of an install.
type Result struct {
	Dir     string
	Written []string // files created or changed
	Removed []string // stale files removed from our folder
}

// Changed reports whether anything on disk changed.
func (r Result) Changed() bool { return len(r.Written)+len(r.Removed) > 0 }

// Install syncs the embedded addon into addOnsDir\NavtokDiscord. Only files that differ are
// written; files in our folder that are not part of the build are removed. Nothing outside our
// folder is touched. WoW picks up changes on the next /reload or login.
func Install(src fs.FS, root, addOnsDir string) (Result, error) {
	dst := filepath.Join(addOnsDir, AddonName)
	res := Result{Dir: dst}
	fl, err := files(src, root)
	if err != nil {
		return res, err
	}
	want := map[string]bool{}
	for _, f := range fl {
		want[filepath.FromSlash(f.rel)] = true
		target := filepath.Join(dst, filepath.FromSlash(f.rel))
		if old, err := os.ReadFile(target); err == nil && bytes.Equal(old, f.data) {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return res, err
		}
		tmp := target + ".navtok-tmp"
		if err := os.WriteFile(tmp, f.data, 0o644); err != nil {
			return res, err
		}
		if err := os.Rename(tmp, target); err != nil {
			os.Remove(tmp)
			return res, err
		}
		res.Written = append(res.Written, path.Clean(f.rel))
	}
	_ = filepath.WalkDir(dst, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(dst, p)
		if !want[rel] {
			if os.Remove(p) == nil {
				res.Removed = append(res.Removed, filepath.ToSlash(rel))
			}
		}
		return nil
	})
	return res, nil
}

// Uninstall removes our addon folder (and only that).
func Uninstall(addOnsDir string) error {
	return os.RemoveAll(filepath.Join(addOnsDir, AddonName))
}
