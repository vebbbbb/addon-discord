package notify

import "testing"

func TestOncePerProblem(t *testing.T) {
	n := 0
	p := New(func(string, string) { n++ })
	p.Report("offline", "x")
	p.Report("offline", "x")
	p.Report("webhook", "y")
	if n != 2 || !p.Active("offline") {
		t.Fatal(n)
	}
	p.Resolve("offline")
	p.Report("offline", "x")
	if n != 3 {
		t.Fatal(n)
	}
}
