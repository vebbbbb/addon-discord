package update

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestNewer(t *testing.T) {
	for _, c := range []struct {
		a, b string
		want bool
	}{{"v1.0.1", "1.0.0", true}, {"v1.0.0", "v1.0.0", false}, {"v0.9.9", "1.0.0", false}, {"v2.0.0-rc1", "1.9.9", true}, {"v1.10.0", "v1.9.0", true}} {
		if Newer(c.a, c.b) != c.want {
			t.Errorf("%s vs %s", c.a, c.b)
		}
	}
}

func TestLatest(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/repos/o/r/releases/latest" {
			w.WriteHeader(404)
			return
		}
		w.Write([]byte(`{"tag_name":"v1.2.0","assets":[{"name":"` + AssetName + `","browser_download_url":"x"}]}`))
	}))
	defer srv.Close()
	APIBase = srv.URL
	r, err := Latest(context.Background(), srv.Client(), "o/r")
	if err != nil || r.Tag != "v1.2.0" || r.Assets[0].Name != AssetName {
		t.Fatal(r, err)
	}
}
