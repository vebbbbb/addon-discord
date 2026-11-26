package barcode

import (
	"bufio"
	"bytes"
	"encoding/hex"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// The fixture is written by the Lua encoder (luajit addon/tests/gen_fixture.lua).
var fixturePath = filepath.Join("..", "..", "..", "addon", "tests", "fixtures", "barcode_v1.txt")

type fixture struct {
	payload, frame []byte
	rows, cols     int
	grid           Grid
}

func loadFixture(t *testing.T) fixture {
	t.Helper()
	f, err := os.Open(fixturePath)
	if err != nil {
		t.Fatalf("open fixture: %v", err)
	}
	defer f.Close()
	var fx fixture
	var gridLines []string
	inGrid := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if inGrid {
			gridLines = append(gridLines, line)
			continue
		}
		k, v, _ := strings.Cut(line, ":")
		v = strings.TrimSpace(v)
		switch k {
		case "payload_hex":
			fx.payload, _ = hex.DecodeString(v)
		case "frame_hex":
			fx.frame, _ = hex.DecodeString(v)
		case "rows":
			fx.rows, _ = strconv.Atoi(v)
		case "cols":
			fx.cols, _ = strconv.Atoi(v)
		case "grid":
			inGrid = true
		}
	}
	fx.grid = Grid{Rows: fx.rows, Cols: fx.cols, Bits: make([]byte, fx.rows*fx.cols)}
	if len(gridLines) != fx.rows {
		t.Fatalf("fixture has %d grid lines, want %d", len(gridLines), fx.rows)
	}
	for r, l := range gridLines {
		if len(l) != fx.cols {
			t.Fatalf("grid line %d has %d cols", r, len(l))
		}
		for c, ch := range l {
			if ch == '1' {
				fx.grid.Bits[r*fx.cols+c] = 1
			}
		}
	}
	return fx
}

func TestLuaFixtureMatchesGoEncoder(t *testing.T) {
	fx := loadFixture(t)
	if fx.rows != Rows || fx.cols != Cols {
		t.Fatalf("fixture dims %dx%d, Go %dx%d", fx.rows, fx.cols, Rows, Cols)
	}
	frame, err := BuildFrame(fx.payload)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(frame, fx.frame) {
		t.Fatalf("frame differs:\n go  %x\n lua %x", frame, fx.frame)
	}
	g := BuildGrid(frame)
	for i := range g.Bits {
		if g.Bits[i] != fx.grid.Bits[i] {
			t.Fatalf("grid differs at row %d col %d", i/Cols, i%Cols)
		}
	}
}

func TestLuaFixtureDecodesFromJPEG(t *testing.T) {
	fx := loadFixture(t)
	for _, q := range []int{50, 75, 95} {
		scene := fakeScene(1920, 1080, 9)
		place(scene, Render(fx.grid, ModulePx, Quiet), "tr")
		res, err := Decode(jpegRoundTrip(t, scene, q))
		if err != nil {
			t.Fatalf("q%d: %v", q, err)
		}
		if !bytes.Equal(res.Payload, fx.payload) {
			t.Fatalf("q%d: payload %q, want %q", q, res.Payload, fx.payload)
		}
	}
}
