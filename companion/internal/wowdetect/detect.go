// Package wowdetect finds WoW installations and picks the WoW Forever client folder.
//
// Heuristic (documented in VERIFY.md item 10 - it is a guess until checked on a real install):
//
//	score +100  folder name contains "forever"                       (e.g. _forever_, _classic_forever_)
//	score  +90  .flavor.info names a product whose .build.info Version starts with "1.60."
//	score  +80  .flavor.info or .build.info product name contains "forever"
//	score  +40  a WoW*.exe in the folder whose name contains "Forever"
//	score  +10  Interface\AddOns\NavtokDiscord already exists (we installed there before)
//
// A client with score >= 60 is "Forever". Several may match (beta + live); all are used.
package wowdetect

import (
	"bufio"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Client is one game client folder inside an installation (e.g. ...\World of Warcraft\_classic_era_).
type Client struct {
	Dir     string
	Name    string // folder name
	Product string // from .flavor.info
	Version string // from .build.info (matched by product)
	Score   int
	Reasons []string
}

// IsForever is the decision threshold.
func (c Client) IsForever() bool { return c.Score >= 60 }

// AddOnsDir, ScreenshotsDir, AccountDir are the paths NAVTOK uses inside a client.
func (c Client) AddOnsDir() string      { return filepath.Join(c.Dir, "Interface", "AddOns") }
func (c Client) ScreenshotsDir() string { return filepath.Join(c.Dir, "Screenshots") }
func (c Client) AccountDir() string     { return filepath.Join(c.Dir, "WTF", "Account") }

// ReadBuildInfo parses <root>\.build.info (pipe separated table, first line = header) into
// product -> version.
func ReadBuildInfo(root string) map[string]string {
	out := map[string]string{}
	f, err := os.Open(filepath.Join(root, ".build.info"))
	if err != nil {
		return out
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	var cols []string
	pi, vi := -1, -1
	for sc.Scan() {
		parts := strings.Split(strings.TrimSpace(sc.Text()), "|")
		if cols == nil {
			cols = parts
			for i, c := range cols {
				name, _, _ := strings.Cut(c, "!")
				switch strings.ToLower(name) {
				case "product":
					pi = i
				case "version":
					vi = i
				}
			}
			continue
		}
		if pi >= 0 && vi >= 0 && pi < len(parts) && vi < len(parts) {
			out[strings.ToLower(parts[pi])] = parts[vi]
		}
	}
	return out
}

// readFlavor returns the product named in <client>\.flavor.info (second non-empty line).
func readFlavor(dir string) string {
	b, err := os.ReadFile(filepath.Join(dir, ".flavor.info"))
	if err != nil {
		return ""
	}
	lines := strings.FieldsFunc(string(b), func(r rune) bool { return r == '\n' || r == '\r' })
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l != "" && !strings.Contains(l, "!") {
			return strings.ToLower(l)
		}
	}
	return ""
}

func isClientFolder(dir, name string) bool {
	if len(name) < 3 || !strings.HasPrefix(name, "_") || !strings.HasSuffix(name, "_") {
		return false
	}
	if st, err := os.Stat(filepath.Join(dir, "Interface")); err == nil && st.IsDir() {
		return true
	}
	exes, _ := filepath.Glob(filepath.Join(dir, "Wow*.exe"))
	return len(exes) > 0
}

// Clients lists the client folders of an installation root and scores them.
func Clients(root string) []Client {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	builds := ReadBuildInfo(root)
	var out []Client
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(root, e.Name())
		if !isClientFolder(dir, e.Name()) {
			continue
		}
		c := Client{Dir: dir, Name: e.Name(), Product: readFlavor(dir)}
		c.Version = builds[c.Product]
		score(&c)
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Score != out[j].Score {
			return out[i].Score > out[j].Score
		}
		return out[i].Name < out[j].Name
	})
	return out
}

func score(c *Client) {
	add := func(n int, why string) { c.Score += n; c.Reasons = append(c.Reasons, why) }
	if strings.Contains(strings.ToLower(c.Name), "forever") {
		add(100, "folder name contains 'forever'")
	}
	if strings.HasPrefix(c.Version, "1.60.") {
		add(90, "client version "+c.Version)
	}
	if strings.Contains(c.Product, "forever") {
		add(80, "product "+c.Product)
	}
	exes, _ := filepath.Glob(filepath.Join(c.Dir, "Wow*.exe"))
	for _, x := range exes {
		if strings.Contains(strings.ToLower(filepath.Base(x)), "forever") {
			add(40, "executable "+filepath.Base(x))
			break
		}
	}
	if st, err := os.Stat(filepath.Join(c.AddOnsDir(), "NavtokDiscord")); err == nil && st.IsDir() {
		add(10, "NavtokDiscord already installed")
	}
}

// Detect returns all clients found under the given roots and the subset judged Forever.
func Detect(roots []string) (all, forever []Client) {
	seen := map[string]bool{}
	for _, r := range roots {
		key := strings.ToLower(filepath.Clean(r))
		if seen[key] {
			continue
		}
		seen[key] = true
		for _, c := range Clients(r) {
			all = append(all, c)
			if c.IsForever() {
				forever = append(forever, c)
			}
		}
	}
	return all, forever
}

// NormalizeRoot turns a registry InstallPath (often ...\World of Warcraft\_retail_\) into the
// installation root.
func NormalizeRoot(p string) string {
	p = strings.TrimRight(strings.TrimSpace(p), `\/`)
	base := filepath.Base(p)
	if strings.HasPrefix(base, "_") && strings.HasSuffix(base, "_") {
		return filepath.Dir(p)
	}
	return p
}

// ClientFromDir builds a Client for a user-chosen folder (the client folder itself, or a root
// with exactly one client).
func ClientFromDir(dir string) (Client, bool) {
	if isClientFolder(dir, filepath.Base(dir)) || dirExists(filepath.Join(dir, "Interface")) {
		c := Client{Dir: dir, Name: filepath.Base(dir)}
		score(&c)
		return c, true
	}
	if cs := Clients(dir); len(cs) == 1 {
		return cs[0], true
	}
	return Client{}, false
}

func dirExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}
