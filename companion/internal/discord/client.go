package discord

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var webhookRe = regexp.MustCompile(`^https://(?:(?:canary|ptb)\.)?discord(?:app)?\.com/api(?:/v\d+)?/webhooks/\d+/[\w-]+$`)

// ValidURL checks the shape of a webhook URL.
func ValidURL(u string) bool { return webhookRe.MatchString(strings.TrimSpace(u)) }

// RateLimitError means Discord answered 429; retry after After.
type RateLimitError struct{ After time.Duration }

func (e *RateLimitError) Error() string {
	return fmt.Sprintf("discord: rate limited, retry after %s", e.After)
}

// PermanentError will not get better by retrying (bad webhook, bad payload).
type PermanentError struct {
	Status int
	Body   string
}

func (e *PermanentError) Error() string {
	return fmt.Sprintf("discord: HTTP %d: %s", e.Status, e.Body)
}

// Client posts to one webhook URL. It never talks to any other host.
type Client struct {
	URL  string
	HTTP *http.Client
	// UserAgent is generic on purpose (no user data).
	UserAgent string
	// bucket state from X-RateLimit-* headers
	blockedUntil time.Time
	now          func() time.Time
	sleep        func(context.Context, time.Duration) error
}

// NewClient returns a client with sane timeouts.
func NewClient(url string) *Client {
	return &Client{URL: strings.TrimSpace(url), HTTP: &http.Client{Timeout: 30 * time.Second},
		UserAgent: "NAVTOK-Discord (https://github.com/navtok/navtok-discord, 1.0)", now: time.Now, sleep: sleepCtx}
}

func sleepCtx(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return nil
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

// Validate checks that the webhook exists (GET returns the webhook object).
func (c *Client) Validate(ctx context.Context) error {
	if !ValidURL(c.URL) {
		return &PermanentError{Status: 0, Body: "this is not a Discord webhook URL"}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.URL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", c.UserAgent)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode != http.StatusOK {
		return &PermanentError{Status: resp.StatusCode, Body: strings.TrimSpace(string(body))}
	}
	var w struct {
		ID   string `json:"id"`
		Type int    `json:"type"`
	}
	if json.Unmarshal(body, &w) != nil || w.ID == "" {
		return &PermanentError{Status: resp.StatusCode, Body: "unexpected answer from Discord"}
	}
	return nil
}

// Post sends one message, optionally with a JPEG attachment. It waits out a known exhausted
// rate-limit bucket first. Errors: *RateLimitError, *PermanentError or a transient error.
func (c *Client) Post(ctx context.Context, msg Message, image []byte) error {
	if wait := c.blockedUntil.Sub(c.now()); wait > 0 {
		if err := c.sleep(ctx, wait); err != nil {
			return err
		}
	}
	body, ctype, err := encode(msg, image)
	if err != nil {
		return &PermanentError{Body: err.Error()}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.URL+"?wait=true", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", ctype)
	req.Header.Set("User-Agent", c.UserAgent)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err // transient (offline, DNS, timeout)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 8192))
	c.trackBucket(resp.Header)
	switch {
	case resp.StatusCode >= 200 && resp.StatusCode < 300:
		return nil
	case resp.StatusCode == http.StatusTooManyRequests:
		return &RateLimitError{After: retryAfter(resp.Header, respBody)}
	case resp.StatusCode >= 500:
		return fmt.Errorf("discord: HTTP %d", resp.StatusCode)
	default:
		return &PermanentError{Status: resp.StatusCode, Body: strings.TrimSpace(string(respBody))}
	}
}

func (c *Client) trackBucket(h http.Header) {
	if h.Get("X-RateLimit-Remaining") != "0" {
		return
	}
	if s, err := strconv.ParseFloat(h.Get("X-RateLimit-Reset-After"), 64); err == nil {
		c.blockedUntil = c.now().Add(time.Duration(s * float64(time.Second)))
	}
}

func retryAfter(h http.Header, body []byte) time.Duration {
	var b struct {
		RetryAfter float64 `json:"retry_after"`
	}
	if json.Unmarshal(body, &b) == nil && b.RetryAfter > 0 {
		return time.Duration(b.RetryAfter*float64(time.Second)) + 50*time.Millisecond
	}
	if s, err := strconv.ParseFloat(h.Get("Retry-After"), 64); err == nil && s > 0 {
		return time.Duration(s * float64(time.Second))
	}
	return 2 * time.Second
}

func encode(msg Message, image []byte) ([]byte, string, error) {
	js, err := json.Marshal(msg)
	if err != nil {
		return nil, "", err
	}
	if len(image) == 0 {
		return js, "application/json", nil
	}
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	h := textproto.MIMEHeader{}
	h.Set("Content-Disposition", `form-data; name="payload_json"`)
	h.Set("Content-Type", "application/json")
	pw, err := w.CreatePart(h)
	if err != nil {
		return nil, "", err
	}
	pw.Write(js)
	h = textproto.MIMEHeader{}
	h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="files[0]"; filename="%s"`, ImageName))
	h.Set("Content-Type", "image/jpeg")
	fw, err := w.CreatePart(h)
	if err != nil {
		return nil, "", err
	}
	fw.Write(image)
	if err := w.Close(); err != nil {
		return nil, "", err
	}
	return buf.Bytes(), w.FormDataContentType(), nil
}

// IsPermanent reports whether err will not go away by retrying.
func IsPermanent(err error) bool {
	var p *PermanentError
	return errors.As(err, &p)
}
