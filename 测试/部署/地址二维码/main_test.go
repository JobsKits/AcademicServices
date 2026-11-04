package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestURLRoundTripAndCredentialRejection(t *testing.T) {
	original := "https://example.com/%E4%B8%AD%E6%96%87/client/?view=mobile&ref=a%26b#section"
	c, err := parseCard("用户端|" + original)
	if err != nil || c.URL != original {
		t.Fatalf("URL changed: %q %v", c.URL, err)
	}
	for _, raw := range []string{"https://user:pass@example.com/", "https://example.com/?token=secret", "http://0.0.0.0:8080/", "http://[::]:8080/", "javascript:alert(1)", "https://example.com/\n"} {
		if _, err := parseCard("入口|" + raw); err == nil {
			t.Errorf("accepted invalid or secret-bearing address")
		}
	}
}

func TestPlainAndNarrowTerminalsHaveNoANSI(t *testing.T) {
	c, _ := parseCard("用户端|https://example.com/client/")
	t.Setenv("NO_COLOR", "")
	var b bytes.Buffer
	terminalCard(&b, c, 200, true)
	if strings.Contains(b.String(), "\x1b") || !strings.Contains(b.String(), c.URL) {
		t.Fatal("NO_COLOR presence must produce plain output")
	}
	b.Reset()
	terminalCard(&b, c, 1, true)
	if strings.Contains(b.String(), "\x1b") {
		t.Fatal("narrow terminal emitted a clipped QR")
	}
}

func TestOfflineFilesAndExpiry(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "中文 空格")
	var b bytes.Buffer
	args := []string{"--output-dir", dir, "--entry", "用户端|https://example.com/client/", "--entry", "管理端|https://example.com/admin/"}
	if err := run(args, &b); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"index.html", "01.svg", "02.svg", "01.png", "02.png"} {
		if st, err := os.Stat(filepath.Join(dir, name)); err != nil || st.Size() == 0 {
			t.Fatalf("missing output %s", name)
		}
	}
	html, _ := os.ReadFile(filepath.Join(dir, "index.html"))
	if !bytes.Contains(html, []byte("https://example.com/admin/")) || !bytes.Contains(html, []byte("<svg")) {
		t.Fatal("page missing inline code or exact URL")
	}
	if err := run([]string{"--expire", "--output-dir", dir}, &b); err != nil {
		t.Fatal(err)
	}
	html, _ = os.ReadFile(filepath.Join(dir, "index.html"))
	if !bytes.Contains(html, []byte("本次部署已结束")) || bytes.Contains(html, []byte("<svg")) {
		t.Fatal("expired page still presents QR")
	}
}

func TestInvalidAddressDoesNotPublishFilesOrSecrets(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "invalid")
	var b bytes.Buffer
	err := run([]string{"--output-dir", dir, "--entry", "管理端|https://admin:secret@example.com/admin/"}, &b)
	if err == nil || strings.Contains(b.String(), "secret") {
		t.Fatal("invalid entry was published")
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatal("validation failure wrote output")
	}
}

func TestSymlinkOutputIsPreserved(t *testing.T) {
	target := t.TempDir()
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(target, link); err != nil {
		t.Skip(err)
	}
	var b bytes.Buffer
	if err := run([]string{"--output-dir", link, "--entry", "入口|https://example.com/"}, &b); err == nil {
		t.Fatal("followed symlink")
	}
	if files, _ := os.ReadDir(target); len(files) != 0 {
		t.Fatal("changed symlink target")
	}
}
