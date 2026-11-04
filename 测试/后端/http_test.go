package platform

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func apiSetup(t *testing.T) (*API, *httptest.Server) {
	t.Helper()
	e := NewEngine(NewMemoryStore())
	api := NewAPI(e, Config{Environment: "test", AdminPassword: "demo-admin-change-me", CustomerPassword: "demo-customer"})
	s := httptest.NewServer(api)
	t.Cleanup(s.Close)
	return api, s
}
func request(t *testing.T, s *httptest.Server, method, path, token, key string, body any) (int, map[string]any) {
	t.Helper()
	var b io.Reader
	if body != nil {
		x, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		b = bytes.NewReader(x)
	}
	r, err := http.NewRequest(method, s.URL+path, b)
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	if key != "" {
		r.Header.Set("Idempotency-Key", key)
	}
	r.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	if err = json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, out
}
func loginToken(t *testing.T, s *httptest.Server, account string) string {
	t.Helper()
	p := "demo-customer"
	if account == "admin" {
		p = "demo-admin-change-me"
	}
	code, out := request(t, s, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": account, "password": p})
	if code != 200 {
		t.Fatalf("login %d %+v", code, out)
	}
	return out["token"].(string)
}
func TestHTTPAuthenticationExpiryAndLogout(t *testing.T) {
	a, s := apiSetup(t)
	code, _ := request(t, s, "GET", "/api/v1/workspace", "", "", nil)
	if code != 401 {
		t.Fatal(code)
	}
	token := loginToken(t, s, "customer")
	code, _ = request(t, s, "GET", "/api/v1/workspace", token, "", nil)
	if code != 200 {
		t.Fatal(code)
	}
	a.engine.Now = func() time.Time { return time.Now().Add(9 * time.Hour) }
	code, _ = request(t, s, "GET", "/api/v1/workspace", token, "", nil)
	if code != 401 {
		t.Fatal("expired session works")
	}
	a.engine.Now = time.Now
	token = loginToken(t, s, "customer")
	code, _ = request(t, s, "POST", "/api/v1/auth/logout", token, "", map[string]any{})
	if code != 200 {
		t.Fatal(code)
	}
	code, _ = request(t, s, "GET", "/api/v1/workspace", token, "", nil)
	if code != 401 {
		t.Fatal("logout did not revoke")
	}
}
func TestHTTPCreateOperationAndForeignIsolation(t *testing.T) {
	_, s := apiSetup(t)
	token := loginToken(t, s, "customer")
	other := loginToken(t, s, "customer2")
	in := CreateInput{ServiceID: "editing", Title: "翻译", Description: "论文摘要", Language: "English", Consent: true}
	code, out := request(t, s, "POST", "/api/v1/cases", token, "http-create-key", in)
	if code != 201 {
		t.Fatalf("%d %+v", code, out)
	}
	c := out["case"].(map[string]any)
	id := c["id"].(string)
	code, out = request(t, s, "GET", "/api/v1/operations/http-create-key", token, "", nil)
	if code != 200 || out["case"].(map[string]any)["id"] != id {
		t.Fatal(code, out)
	}
	for _, path := range []string{"/api/v1/cases/" + id, "/api/v1/operations/http-create-key"} {
		code, _ = request(t, s, "GET", path, other, "", nil)
		if code != 404 {
			t.Fatal("foreign visible", path, code)
		}
	}
	code, out = request(t, s, "GET", "/api/v1/workspace", other, "", nil)
	if code != 200 || len(out["cases"].([]any)) != 0 {
		t.Fatal(out)
	}
	code, _ = request(t, s, "POST", "/api/v1/cases/"+id+"/actions", token, "http-message-key", Action{Action: "message", ExpectedVersion: 1, Text: "补充说明"})
	if code != 200 {
		t.Fatal(code)
	}
	code, _ = request(t, s, "POST", "/api/v1/cases/"+id+"/actions", token, "http-stale-key", Action{Action: "message", ExpectedVersion: 1, Text: "旧版本"})
	if code != 409 {
		t.Fatal(code)
	}
}
func TestHTTPPrivateAttachmentRoundTrip(t *testing.T) {
	a, s := apiSetup(t)
	token := loginToken(t, s, "customer")
	other := loginToken(t, s, "customer2")
	c, err := a.engine.Create(testCtx, testCustomer, "upload-case-key", CreateInput{ServiceID: "editing", Title: "翻译", Description: "摘要", Language: "英文", Consent: true})
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	part, err := mw.CreateFormFile("file", "材料.txt")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = part.Write([]byte("private content"))
	_ = mw.WriteField("expected_version", strconv.Itoa(c.Version))
	_ = mw.Close()
	r, _ := http.NewRequest("POST", s.URL+"/api/v1/cases/"+c.ID+"/attachments", &buf)
	r.Header.Set("Content-Type", mw.FormDataContentType())
	r.Header.Set("Authorization", "Bearer "+token)
	r.Header.Set("Idempotency-Key", "upload-http-key")
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	var out struct {
		Case Case `json:"case"`
	}
	err = json.NewDecoder(resp.Body).Decode(&out)
	resp.Body.Close()
	if err != nil || resp.StatusCode != 201 || len(out.Case.Attachments) != 1 {
		t.Fatalf("upload %d %+v %v", resp.StatusCode, out, err)
	}
	if len(out.Case.Attachments[0].Data) != 0 {
		t.Fatal("binary included in public response")
	}
	path := "/api/v1/cases/" + c.ID + "/attachments/" + out.Case.Attachments[0].ID
	code, _ := request(t, s, "GET", path, other, "", nil)
	if code != 404 {
		t.Fatal("foreign file", code)
	}
	r, _ = http.NewRequest("GET", s.URL+path, nil)
	r.Header.Set("Authorization", "Bearer "+token)
	resp, err = http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || string(b) != "private content" || !strings.HasPrefix(resp.Header.Get("Content-Disposition"), "attachment;") || resp.Header.Get("Content-Type") != "application/octet-stream" {
		t.Fatal("unsafe attachment response", resp.StatusCode, string(b), resp.Header)
	}
}
func TestHTTPRejectMalformedUnknownLargeAndRoleActions(t *testing.T) {
	_, s := apiSetup(t)
	token := loginToken(t, s, "customer")
	for _, body := range []string{`{"unknown":true}`, `{} {}`, strings.Repeat("x", 300000)} {
		r, _ := http.NewRequest("POST", s.URL+"/api/v1/cases", strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("Idempotency-Key", "bad-json-key")
		resp, err := http.DefaultClient.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != 422 {
			t.Fatal(resp.StatusCode)
		}
	}
	code, _ := request(t, s, "POST", "/api/v1/cases/unknown/actions", token, "role-test-key", Action{Action: "quote", ExpectedVersion: 1})
	if code != 403 {
		t.Fatal("customer may quote", code)
	}
	code, _ = request(t, s, "GET", "/api/v1/admin/outbox", token, "", nil)
	if code != 403 {
		t.Fatal(code)
	}
}
func TestHTTPLoginRateLimit(t *testing.T) {
	_, s := apiSetup(t)
	for i := 0; i < 11; i++ {
		code, _ := request(t, s, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": "missing", "password": "wrong"})
		want := 401
		if i == 10 {
			want = 429
		}
		if code != want {
			t.Fatalf("attempt%d got %d", i, code)
		}
	}
}
func TestHTTPOriginReverseProxyAndPreflight(t *testing.T) {
	a, _ := apiSetup(t)
	a.config.Environment = "production"
	for _, tc := range []struct {
		host, origin string
		want         int
	}{{"service.example", "https://service.example", 200}, {"service.example", "https://evil.example", 403}, {"127.0.0.1:8080", "http://127.0.0.1:8080", 200}, {"service.example", "http://service.example", 403}, {"service.example", "https://service.example/anything", 403}} {
		r := httptest.NewRequest("GET", "http://"+tc.host+"/api/v1/services", nil)
		r.Host = tc.host
		r.Header.Set("Origin", tc.origin)
		w := httptest.NewRecorder()
		a.ServeHTTP(w, r)
		if w.Code != tc.want {
			t.Fatalf("%s %s=>%d", tc.host, tc.origin, w.Code)
		}
	}
	a.config.Origins = []string{"https://admin.example"}
	r := httptest.NewRequest("OPTIONS", "http://service.example/api/v1/cases", nil)
	r.Header.Set("Origin", "https://admin.example")
	w := httptest.NewRecorder()
	a.ServeHTTP(w, r)
	if w.Code != 204 || w.Header().Get("Access-Control-Allow-Origin") != "https://admin.example" {
		t.Fatal(w)
	}
}
func TestHTTPStaticAndHealth(t *testing.T) {
	a, s := apiSetup(t)
	code, _ := request(t, s, "GET", "/healthz", "", "", nil)
	if code != 200 {
		t.Fatal(code)
	}
	dir := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, "index.html"), []byte("<h1>admin</h1>"), 0600)
	a.config.AdminStaticDir = dir
	a.static = http.StripPrefix("/admin/", http.FileServer(http.Dir(dir)))
	resp, err := http.Get(s.URL + "/admin/")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !strings.Contains(string(b), "admin") {
		t.Fatal("static", resp.StatusCode)
	}
}
func TestConfigProductionRejectsDefaults(t *testing.T) {
	for _, name := range []string{"APP_ENV", "LISTEN_ADDR", "ADMIN_PASSWORD", "DEMO_CUSTOMER_PASSWORD", "CORS_ORIGINS", "LOCAL_DEBUG_PASSWORDS"} {
		t.Setenv(name, "")
	}
	t.Setenv("APP_ENV", "production")
	_, err := LoadConfig()
	if err == nil {
		t.Fatal("production accepted defaults")
	}
	t.Setenv("ADMIN_PASSWORD", "a-strong-admin-password")
	t.Setenv("DEMO_CUSTOMER_PASSWORD", "a-strong-customer-password")
	c, err := LoadConfig()
	if err != nil {
		t.Fatal(err)
	}
	api := NewAPI(NewEngine(NewMemoryStore()), c)
	if _, ok := api.credentials["customer2"]; ok {
		t.Fatal("test account seeded in production")
	}
	t.Setenv("CORS_ORIGINS", "*")
	if _, err = LoadConfig(); err == nil {
		t.Fatal("wildcard production cors")
	}
}
func TestConfigLocalDebugPasswordPolicy(t *testing.T) {
	for _, tc := range []struct {
		name, debug, listen, admin, customer, origins, wantError string
	}{
		{"local four characters", "1", "127.0.0.1:8080", "adm4", "usr4", "", ""},
		{"IPv6 loopback", "1", "[::1]:8080", "adm4", "usr4", "", ""},
		{"local three characters", "1", "127.0.0.1:8080", "adm", "usr4", "", "at least 4 characters"},
		{"local three customer characters", "1", "127.0.0.1:8080", "adm4", "usr", "", "at least 4 characters"},
		{"Unicode four characters", "1", "127.0.0.1:8080", "管理密码", "客户密码", "", ""},
		{"Unicode three characters", "1", "127.0.0.1:8080", "密码短", "usr4", "", "at least 4 characters"},
		{"production without debug", "", "127.0.0.1:8080", "adm4", "usr4", "", "at least 12 characters"},
		{"explicit debug required", "true", "127.0.0.1:8080", "adm4", "usr4", "", "at least 12 characters"},
		{"all interfaces", "1", "0.0.0.0:8080", "adm4", "usr4", "", "at least 12 characters"},
		{"IPv6 all interfaces", "1", "[::]:8080", "adm4", "usr4", "", "at least 12 characters"},
		{"non-loopback", "1", "192.0.2.1:8080", "adm4", "usr4", "", "at least 12 characters"},
		{"hostname does not relax policy", "1", "localhost:8080", "adm4", "usr4", "", "at least 12 characters"},
		{"duplicate accounts", "1", "127.0.0.1:8080", "adm4", "adm4", "", "distinct"},
		{"default administrator", "1", "127.0.0.1:8080", "demo-admin-change-me", "usr4", "", "no demo defaults"},
		{"default customer", "1", "127.0.0.1:8080", "adm4", "demo-customer", "", "no demo defaults"},
		{"wildcard CORS", "1", "127.0.0.1:8080", "adm4", "usr4", "*", "CORS_ORIGINS"},
		{"HTTP CORS", "1", "127.0.0.1:8080", "adm4", "usr4", "http://service.example", "CORS_ORIGINS"},
		{"HTTPS CORS", "1", "127.0.0.1:8080", "adm4", "usr4", "https://service.example", ""},
		{"non-loopback strong passwords", "1", "0.0.0.0:8080", "admin-password-123", "customer-password-123", "", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for name, value := range map[string]string{
				"APP_ENV":                "production",
				"LOCAL_DEBUG_PASSWORDS":  tc.debug,
				"LISTEN_ADDR":            tc.listen,
				"ADMIN_PASSWORD":         tc.admin,
				"DEMO_CUSTOMER_PASSWORD": tc.customer,
				"CORS_ORIGINS":           tc.origins,
			} {
				t.Setenv(name, value)
			}
			c, err := LoadConfig()
			if tc.wantError != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantError) {
					t.Fatalf("expected %q, got %v", tc.wantError, err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if c.Environment != "production" {
				t.Fatal("local debug changed production environment")
			}
			api := NewAPI(NewEngine(NewMemoryStore()), c)
			if _, ok := api.credentials["customer2"]; ok {
				t.Fatal("local debug seeded test account")
			}
			r := httptest.NewRequest("GET", "http://service.example/api/v1/services", nil)
			r.Header.Set("Origin", "http://service.example")
			w := httptest.NewRecorder()
			api.ServeHTTP(w, r)
			if w.Code != http.StatusForbidden {
				t.Fatal("local debug relaxed public HTTP origin policy", w.Code)
			}
		})
	}
}
func TestStaticSPAAndPrivateDirectoryBoundary(t *testing.T) {
	dir := t.TempDir()
	outside := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, "index.html"), []byte("<h1>client shell</h1>"), 0600)
	_ = os.WriteFile(filepath.Join(dir, "app.js"), []byte("console.log('client')"), 0600)
	_ = os.WriteFile(filepath.Join(outside, "secret.txt"), []byte("secret"), 0600)
	if err := os.Symlink(filepath.Join(outside, "secret.txt"), filepath.Join(dir, "escape.txt")); err != nil {
		t.Log("symlink fixture not available", err)
	}
	handler := spa(dir, "/client/")
	for _, tc := range []struct {
		path string
		want int
	}{{"/client/", 200}, {"/client/orders/123", 200}, {"/client/app.js", 200}, {"/client/missing.js", 404}, {"/client/../secret.txt", 404}, {"/client/escape.txt", 404}} {
		r := httptest.NewRequest("GET", "http://localhost"+tc.path, nil)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		if w.Code != tc.want {
			t.Fatalf("%s => %d", tc.path, w.Code)
		}
		if strings.Contains(w.Body.String(), "secret") {
			t.Fatalf("private file leaked by %s", tc.path)
		}
	}
}
