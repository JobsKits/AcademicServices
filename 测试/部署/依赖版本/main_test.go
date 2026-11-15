package main

import (
	"bytes"
	"crypto/x509"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const testSHA = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

// 只在单测transport映射官方端点；生产二进制没有源覆盖入口。
func metadataClient(t *testing.T, endpoint string, body any, status int, headers ...map[string]string) *http.Client {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for _, values := range headers {
			for name, value := range values {
				w.Header().Set(name, value)
			}
		}
		if r.Method != "GET" || r.Header.Get("User-Agent") == "" {
			t.Error("missing bounded metadata request contract")
		}
		w.WriteHeader(status)
		if raw, ok := body.(string); ok {
			_, _ = io.WriteString(w, raw)
			return
		}
		_ = json.NewEncoder(w).Encode(body)
	}))
	t.Cleanup(server.Close)
	local, _ := url.Parse(server.URL)
	return &http.Client{Timeout: time.Second, Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if r.URL.String() != endpoint {
			t.Fatalf("unexpected metadata source: %s", r.URL)
		}
		if _, ok := r.Context().Deadline(); !ok {
			t.Error("metadata query lacks deadline")
		}
		copy := r.Clone(r.Context())
		u := *r.URL
		u.Scheme, u.Host = local.Scheme, local.Host
		copy.URL = &u
		return http.DefaultTransport.RoundTrip(copy)
	})}
}
func execute(t *testing.T, client *http.Client, args ...string) (int, string, string) {
	t.Helper()
	var out, stderr bytes.Buffer
	code := run(args, &out, &stderr, client)
	return code, out.String(), stderr.String()
}
func goArchive(version, platform, arch string) map[string]any {
	ext := ".tar.gz"
	if platform == "windows" {
		ext = ".zip"
	}
	return map[string]any{"filename": version + "." + platform + "-" + arch + ext, "os": platform, "arch": arch, "version": version, "sha256": testSHA, "kind": "archive"}
}
func githubFixture(tag, name, address, digest string) map[string]any {
	return map[string]any{"tag_name": tag, "draft": false, "prerelease": false, "assets": []map[string]any{{"name": name, "browser_download_url": address, "digest": digest}}}
}

func TestNumericVersionComparisonAndCLI(t *testing.T) {
	for _, item := range []struct{ left, right, result string }{
		{"go1.27.4", "1.27.3", "1\n"}, {"v0.75.0", "0.9.0", "1\n"}, {"2026.10.7", "2026.11.0", "0\n"}, {"1.27", "1.27.0", "1\n"}, {"1.10.0", "1.9.99", "1\n"},
	} {
		code, out, stderr := execute(t, nil, "--compare", item.left, "--at-least", item.right)
		wantCode := 0
		if item.result == "0\n" {
			wantCode = 1
		}
		if code != wantCode || out != item.result || stderr != "" {
			t.Fatalf("compare %+v: %d %q %q", item, code, out, stderr)
		}
	}
	for _, bad := range []string{"1.27rc1", "v0.75.0-extra", "1.27.4\n", "01.2.3", "1.2.3.4", "99999999999999.1.0", "1", "1.2\tbad"} {
		code, out, stderr := execute(t, nil, "--compare", bad, "--at-least", "1.0.0")
		if code == 0 || out != "" || stderr == "" {
			t.Fatalf("accepted bad version %q", bad)
		}
	}
}
func TestGoSelectsNewestStableAndTargetArchive(t *testing.T) {
	body := []map[string]any{
		{"version": "go1.26.8", "stable": true, "files": []any{goArchive("go1.26.8", "darwin", "arm64")}},
		{"version": "go1.28rc1", "stable": false, "files": []any{}},
		{"version": "go1.27.4", "stable": true, "files": []any{goArchive("go1.27.4", "darwin", "amd64"), goArchive("go1.27.4", "darwin", "arm64")}},
	}
	client := metadataClient(t, goMetadataURL, body, 200)
	code, out, stderr := execute(t, client, "--tool", "go", "--os", "darwin", "--arch", "arm64", "--minimum-go", "1.24.0")
	want := "go\tdarwin\tarm64\t1.27.4\tgo1.27.4.darwin-arm64.tar.gz\t" + testSHA + "\thttps://go.dev/dl/go1.27.4.darwin-arm64.tar.gz\ttar.gz\n"
	if code != 0 || out != want || stderr != "" {
		t.Fatalf("%d %q %q", code, out, stderr)
	}
	code, out, stderr = execute(t, client, "--tool", "go", "--os", "darwin", "--arch", "arm64", "--minimum-go", "1.28.0")
	if code == 0 || out != "" || stderr == "" {
		t.Fatal("minimum not enforced")
	}
}
func TestGoUnsupportedDoesNotChooseOlderRelease(t *testing.T) {
	body := []map[string]any{
		{"version": "go1.27.4", "stable": true, "files": []any{goArchive("go1.27.4", "linux", "amd64")}},
		{"version": "go1.26.8", "stable": true, "files": []any{goArchive("go1.26.8", "freebsd", "arm64")}},
	}
	code, out, stderr := execute(t, metadataClient(t, goMetadataURL, body, 200), "--tool", "go", "--os", "freebsd", "--arch", "arm64")
	if code != 0 || out != "go\tfreebsd\tarm64\t1.27.4\t-\t-\t-\tunsupported\n" || stderr != "" {
		t.Fatalf("%d %q %q", code, out, stderr)
	}
}
func TestGoRejectsMalformedOfficialRecord(t *testing.T) {
	for _, field := range []string{"filename", "sha256", "version", "duplicate", "tag"} {
		t.Run(field, func(t *testing.T) {
			file := goArchive("go1.27.4", "windows", "amd64")
			files := []any{file}
			tag := "go1.27.4"
			switch field {
			case "filename":
				file[field] = "go1.27.4.windows-arm64.zip"
			case "sha256":
				file[field] = "sha256:" + testSHA
			case "version":
				file[field] = "go1.27.3"
			case "duplicate":
				files = append(files, file)
			case "tag":
				tag = "go1.27rc1"
			}
			body := []map[string]any{{"version": tag, "stable": true, "files": files}}
			code, out, stderr := execute(t, metadataClient(t, goMetadataURL, body, 200), "--tool", "go", "--os", "windows", "--arch", "amd64")
			if code == 0 || out != "" || stderr == "" {
				t.Fatalf("accepted %s", field)
			}
		})
	}
}
func TestGitHubAssetsUseExactOfficialNamesAndDigest(t *testing.T) {
	for _, item := range []struct{ tool, platform, arch, tag, name, kind, repo string }{
		{"fzf", "darwin", "arm64", "v0.75.0", "fzf-0.75.0-darwin_arm64.tar.gz", "tar.gz", "junegunn/fzf"},
		{"fzf", "windows", "amd64", "v0.75.0", "fzf-0.75.0-windows_amd64.zip", "zip", "junegunn/fzf"},
		{"fzf", "freebsd", "amd64", "v0.75.0", "fzf-0.75.0-freebsd_amd64.tar.gz", "tar.gz", "junegunn/fzf"},
		{"cloudflared", "darwin", "amd64", "2026.11.0", "cloudflared-darwin-amd64.tgz", "tar.gz", "cloudflare/cloudflared"},
		{"cloudflared", "linux", "arm64", "2026.11.0", "cloudflared-linux-arm64", "binary", "cloudflare/cloudflared"},
		{"cloudflared", "windows", "amd64", "2026.11.0", "cloudflared-windows-amd64.exe", "binary", "cloudflare/cloudflared"},
	} {
		t.Run(item.tool+item.platform, func(t *testing.T) {
			address := "https://github.com/" + item.repo + "/releases/download/" + item.tag + "/" + item.name
			client := metadataClient(t, "https://api.github.com/repos/"+item.repo+"/releases/latest", githubFixture(item.tag, item.name, address, "sha256:"+strings.ToUpper(testSHA)), 200)
			code, out, stderr := execute(t, client, "--tool", item.tool, "--os", item.platform, "--arch", item.arch)
			version := strings.TrimPrefix(item.tag, "v")
			want := strings.Join([]string{item.tool, item.platform, item.arch, version, item.name, testSHA, address, item.kind}, "\t") + "\n"
			if code != 0 || out != want || stderr != "" {
				t.Fatalf("%d %q %q", code, out, stderr)
			}
		})
	}
}
func TestGitHubUnsupportedNeverMixesArchitecture(t *testing.T) {
	body := githubFixture("2026.11.0", "cloudflared-windows-amd64.exe", "https://github.com/cloudflare/cloudflared/releases/download/2026.11.0/cloudflared-windows-amd64.exe", "sha256:"+testSHA)
	code, out, stderr := execute(t, metadataClient(t, "https://api.github.com/repos/cloudflare/cloudflared/releases/latest", body, 200), "--tool", "cloudflared", "--os", "windows", "--arch", "arm64")
	if code != 0 || out != "cloudflared\twindows\tarm64\t2026.11.0\t-\t-\t-\tunsupported\n" || stderr != "" {
		t.Fatalf("%d %q %q", code, out, stderr)
	}
}
func TestGitHubRejectsUnsafeMetadata(t *testing.T) {
	name := "fzf-0.75.0-linux_amd64.tar.gz"
	address := "https://github.com/junegunn/fzf/releases/download/v0.75.0/" + name
	for _, issue := range []string{"draft", "prerelease", "tag", "missing-v", "digest", "bad-host", "credential-url", "query-url", "duplicate"} {
		t.Run(issue, func(t *testing.T) {
			body := githubFixture("v0.75.0", name, address, "sha256:"+testSHA)
			assets := body["assets"].([]map[string]any)
			switch issue {
			case "draft", "prerelease":
				body[issue] = true
			case "tag":
				body["tag_name"] = "v0.75.0rc1"
			case "missing-v":
				body["tag_name"] = "0.75.0"
			case "digest":
				assets[0]["digest"] = "md5:" + testSHA
			case "bad-host":
				assets[0]["browser_download_url"] = "https://example.com/" + name
			case "credential-url":
				assets[0]["browser_download_url"] = "https://user@github.com/junegunn/fzf/releases/download/v0.75.0/" + name
			case "query-url":
				assets[0]["browser_download_url"] = address + "?download=1"
			case "duplicate":
				body["assets"] = append(assets, assets[0])
			}
			code, out, stderr := execute(t, metadataClient(t, "https://api.github.com/repos/junegunn/fzf/releases/latest", body, 200), "--tool", "fzf", "--os", "linux", "--arch", "amd64")
			wantCode := 2
			if issue == "rate-limit" || issue == "too-many" || issue == "server" || issue == "timeout" {
				wantCode = 75
			}
			if code != wantCode || out != "" || stderr == "" {
				t.Fatalf("accepted %s: code %d want %d", issue, code, wantCode)
			}
		})
	}
}
func TestMissingDigestOnlyUsesExactControlledLock(t *testing.T) {
	name := "fzf-0.75.0-linux_amd64.tar.gz"
	address := "https://github.com/junegunn/fzf/releases/download/v0.75.0/" + name
	base := []string{"fzf", "linux", "amd64", "0.75.0", name, testSHA, address, "tar.gz"}
	for _, issue := range []string{"valid", "old-version", "wrong-os", "wrong-arch", "wrong-file", "wrong-url", "wrong-kind", "bad-sha", "duplicate", "malformed", "missing"} {
		t.Run(issue, func(t *testing.T) {
			fields := append([]string(nil), base...)
			switch issue {
			case "old-version":
				fields[3] = "0.74.5"
			case "wrong-os":
				fields[1] = "darwin"
			case "wrong-arch":
				fields[2] = "arm64"
			case "wrong-file":
				fields[4] = "other"
			case "wrong-url":
				fields[6] = "https://example.com/"
			case "wrong-kind":
				fields[7] = "binary"
			case "bad-sha":
				fields[5] = "bad"
			}
			raw := strings.Join(manifestHeader, "\t") + "\n" + strings.Join(fields, "\t") + "\n"
			if issue == "duplicate" {
				raw += strings.Join(fields, "\t") + "\n"
			}
			if issue == "malformed" {
				raw = "not a manifest"
			}
			path := filepath.Join(t.TempDir(), "tools.tsv")
			if err := os.WriteFile(path, []byte(raw), 0600); err != nil {
				t.Fatal(err)
			}
			args := []string{"--tool", "fzf", "--os", "linux", "--arch", "amd64"}
			if issue != "missing" {
				args = append(args, "--locked-manifest", path)
			}
			code, out, stderr := execute(t, metadataClient(t, "https://api.github.com/repos/junegunn/fzf/releases/latest", githubFixture("v0.75.0", name, address, ""), 200), args...)
			if issue == "valid" {
				if code != 0 || out != strings.Join(base, "\t")+"\n" || stderr != "" {
					t.Fatalf("valid fallback: %d %q %q", code, out, stderr)
				}
			} else if code == 0 || out != "" || stderr == "" {
				t.Fatalf("accepted %s fallback", issue)
			}
		})
	}
}
func TestHTTPJSONAndNetworkFailuresProduceNoSuccessRow(t *testing.T) {
	for _, issue := range []string{"rate-limit", "forbidden", "too-many", "server", "html", "trailing", "oversize", "timeout"} {
		t.Run(issue, func(t *testing.T) {
			var client *http.Client
			if issue == "timeout" {
				client = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) { return nil, errors.New("synthetic deadline exceeded") })}
			} else {
				status := 200
				body := "{}"
				switch issue {
				case "rate-limit", "forbidden":
					status = 403
				case "too-many":
					status = 429
				case "server":
					status = 503
				case "html":
					body = "<html>error</html>"
				case "trailing":
					body = "{} {}"
				case "oversize":
					body = strings.Repeat(" ", metadataLimit+1)
				}
				headers := map[string]string{}
				if issue == "rate-limit" {
					headers["X-RateLimit-Remaining"] = "0"
				}
				client = metadataClient(t, "https://api.github.com/repos/junegunn/fzf/releases/latest", body, status, headers)
			}
			code, out, stderr := execute(t, client, "--tool", "fzf", "--os", "linux", "--arch", "amd64")
			wantCode := 2
			if issue == "rate-limit" || issue == "too-many" || issue == "server" || issue == "timeout" {
				wantCode = 75
			}
			if code != wantCode || out != "" || stderr == "" {
				t.Fatalf("accepted %s: code %d want %d", issue, code, wantCode)
			}
		})
	}
	client := officialClient()
	if client.Timeout != queryTimeout || client.CheckRedirect(&http.Request{}, nil) == nil {
		t.Fatal("unbounded production client or redirect accepted")
	}
}
func TestCLIRejectsSourceOverridesAndInvalidSelectors(t *testing.T) {
	for _, args := range [][]string{
		{"--tool", "go", "--os", "linux", "--arch", "386"}, {"--tool", "other", "--os", "linux", "--arch", "amd64"},
		{"--tool", "go", "--os", "other", "--arch", "amd64"}, {"--tool", "go", "--os", "linux", "--arch", "amd64", "--url", "http://example.com"},
		{"--compare", "1.2.3"}, {"--compare", "1.2.3", "--at-least", "1.2.3", "--tool", "go"},
		{"--tool", "fzf", "--os", "linux", "--arch", "amd64", "--minimum-go", "1.24"}, {"--tool", "go", "--os", "linux", "--arch", "amd64", "--minimum-go", "rc"},
	} {
		code, out, stderr := execute(t, nil, args...)
		if code == 0 || out != "" || stderr == "" {
			t.Fatalf("accepted args %q", args)
		}
	}
}

func TestSourceRedirectAndCertificateFailuresAreNotRetried(t *testing.T) {
	for _, issue := range []string{"redirect", "certificate"} {
		t.Run(issue, func(t *testing.T) {
			client := officialClient()
			client.Transport = roundTripFunc(func(r *http.Request) (*http.Response, error) {
				if issue == "certificate" {
					return nil, x509.UnknownAuthorityError{}
				}
				return &http.Response{StatusCode: 302, Header: http.Header{"Location": []string{"https://example.invalid/metadata"}}, Body: io.NopCloser(strings.NewReader("")), Request: r}, nil
			})
			code, out, stderr := execute(t, client, "--tool", "go", "--os", "linux", "--arch", "amd64")
			if code != 2 || out != "" || stderr == "" {
				t.Fatalf("%s returned %d %q %q", issue, code, out, stderr)
			}
		})
	}
}
