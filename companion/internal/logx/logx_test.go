package logx

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCapped(t *testing.T) {
	old := Max
	Max = 4096
	defer func() { Max = old }()
	p := filepath.Join(t.TempDir(), "navtok.log")
	c, err := Open(p, nil)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 1000; i++ {
		c.Write([]byte(strings.Repeat("x", 40) + "\n"))
	}
	c.Write([]byte("last line\n"))
	c.Close()
	b, _ := os.ReadFile(p)
	if int64(len(b)) > Max || !strings.HasSuffix(string(b), "last line\n") || !strings.HasPrefix(string(b), "xxxx") {
		t.Fatalf("size %d", len(b))
	}
}
