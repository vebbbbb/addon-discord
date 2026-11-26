package event

import "testing"

func TestPayloadRoundTrip(t *testing.T) {
	e := &Event{Type: "bg", Test: true, TS: 1764160000, Seq: 7, Char: "Navtök", ClassID: 4, Level: 60,
		Data: map[string]string{"bg": "Warsong Gulch", "result": "win", "duration": "1234", "kb": "7", "hk": "31", "deaths": "2", "honor": "412"}}
	got, err := ParsePayload(EncodePayload(e))
	if err != nil {
		t.Fatal(err)
	}
	if got.Key() != "Navtök|1764160000.7" || !got.Test || got.Class != "ROGUE" || got.Level != 60 {
		t.Fatalf("bad event %+v", got)
	}
	if got.Int("honor") != 412 || got.Get("bg") != "Warsong Gulch" || got.Source != FromBarcode {
		t.Fatalf("bad data %+v", got.Data)
	}
}

func TestParsePayloadFromLuaFixture(t *testing.T) {
	// payload of addon/tests/fixtures/barcode_v1.txt
	p := []byte("L\x1f\x1f1764160000\x1f42\x1fNavt\xc3\xb6k\x1f8\x1f60\x1f19019\x1f5\x1f1\x1fThunderfury, Blessed Blade of the Windseeker")
	e, err := ParsePayload(p)
	if err != nil {
		t.Fatal(err)
	}
	if e.Type != "loot" || e.Test || e.ID != "1764160000.42" || e.Char != "Navtök" || e.Class != "MAGE" {
		t.Fatalf("%+v", e)
	}
	if e.Int("itemId") != 19019 || e.Int("quality") != 5 || e.Get("item") != "Thunderfury, Blessed Blade of the Windseeker" {
		t.Fatalf("%+v", e.Data)
	}
}

func TestParsePayloadErrors(t *testing.T) {
	for _, p := range []string{"", "X\x1f\x1f1\x1f1\x1fa\x1f1\x1f1", "L\x1f\x1fnope\x1f1\x1fa\x1f1\x1f1", "L\x1f\x1f1"} {
		if _, err := ParsePayload([]byte(p)); err == nil {
			t.Errorf("accepted %q", p)
		}
	}
}

func TestParseJSONLine(t *testing.T) {
	line := `{"char":"Testchar","class":"WARRIOR","classId":1,"data":{"count":1,"item":"TF","itemId":19019,"quality":5},"id":"1764160003.1","level":20,"realm":"Testrealm","seq":1,"shot":1764160004,"test":false,"ts":1764160003,"type":"loot"}`
	e, err := ParseJSON(line)
	if err != nil {
		t.Fatal(err)
	}
	if e.Key() != "Testchar|1764160003.1" || e.Shot != 1764160004 || e.Get("itemId") != "19019" || e.Realm != "Testrealm" {
		t.Fatalf("%+v", e)
	}
	if e.Source != FromSavedVars {
		t.Fatal("source")
	}
}

func TestCandidateFlag(t *testing.T) {
	e := &Event{Type: "dungeon", Test: true, Candidate: true, TS: 5, Seq: 9, Char: "A", Data: map[string]string{"encounter": "X"}}
	got, err := ParsePayload(EncodePayload(e))
	if err != nil || !got.Candidate || !got.Test || CandidateKey(got.Char, got.Seq) != "A#9" {
		t.Fatal(got, err)
	}
	j, _ := ParseJSON(`{"candidate":true,"char":"A","data":{},"id":"5.9","seq":9,"ts":5,"type":"dungeon"}`)
	if !j.Candidate {
		t.Fatal("json candidate")
	}
}
