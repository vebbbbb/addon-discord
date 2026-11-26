package wowdetect

import (
	"os"
	"path/filepath"
	"testing"
)

func mk(t *testing.T, root, client, flavor string) string {
	d := filepath.Join(root, client)
	os.MkdirAll(filepath.Join(d, "Interface", "AddOns"), 0o755)
	if flavor != "" {
		os.WriteFile(filepath.Join(d, ".flavor.info"), []byte("Product Flavor!STRING:0\n"+flavor+"\n"), 0o644)
	}
	return d
}

const buildInfo = "Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|Version!STRING:0|Product!STRING:0\n" +
	"eu|1|aa|11.0.5.57689|wow\n" +
	"eu|1|bb|1.15.4.56738|wow_classic_era\n" +
	"eu|1|cc|1.60.1.60123|wow_classic_beta\n"

func TestDetectByBuildVersion(t *testing.T) {
	root := t.TempDir()
	mk(t, root, "_retail_", "wow")
	mk(t, root, "_classic_era_", "wow_classic_era")
	mk(t, root, "_classic_beta_", "wow_classic_beta")
	os.MkdirAll(filepath.Join(root, "_notaclient_"), 0o755) // no Interface
	os.MkdirAll(filepath.Join(root, "Data"), 0o755)
	os.WriteFile(filepath.Join(root, ".build.info"), []byte(buildInfo), 0o644)
	all, fv := Detect([]string{root, root})
	if len(all) != 3 {
		t.Fatalf("all %+v", all)
	}
	if len(fv) != 1 || fv[0].Name != "_classic_beta_" || fv[0].Version != "1.60.1.60123" {
		t.Fatalf("forever %+v", fv)
	}
}

func TestDetectByName(t *testing.T) {
	root := t.TempDir()
	mk(t, root, "_classic_era_", "")
	mk(t, root, "_forever_", "")
	_, fv := Detect([]string{root})
	if len(fv) != 1 || fv[0].Name != "_forever_" {
		t.Fatalf("%+v", fv)
	}
	if fv[0].AddOnsDir() != filepath.Join(root, "_forever_", "Interface", "AddOns") {
		t.Fatal(fv[0].AddOnsDir())
	}
}

func TestNoForever(t *testing.T) {
	root := t.TempDir()
	mk(t, root, "_retail_", "wow")
	all, fv := Detect([]string{root})
	if len(all) != 1 || len(fv) != 0 {
		t.Fatal(all, fv)
	}
}

func TestNormalizeRootAndFromDir(t *testing.T) {
	root := t.TempDir()
	d := mk(t, root, "_classic_era_", "")
	if NormalizeRoot(d+string(filepath.Separator)) != root {
		t.Fatal(NormalizeRoot(d))
	}
	if c, ok := ClientFromDir(d); !ok || c.Dir != d {
		t.Fatal("client dir")
	}
	if c, ok := ClientFromDir(root); !ok || c.Dir != d {
		t.Fatal("root with one client")
	}
}
