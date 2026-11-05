package platform

import (
	"context"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

type Config struct {
	Environment      string
	Listen           string
	DataDir          string
	DatabaseURL      string
	AdminStaticDir   string
	ClientStaticDir  string
	Origins          []string
	AdminPassword    string
	CustomerPassword string
	PaymentMode      string
}

func LoadConfig() (Config, error) {
	c := Config{Environment: env("APP_ENV", "development"), Listen: env("LISTEN_ADDR", "127.0.0.1:8080"), DataDir: env("DATA_DIR", "./data"), DatabaseURL: os.Getenv("DATABASE_URL"), AdminStaticDir: env("ADMIN_STATIC_DIR", "./admin-web"), ClientStaticDir: env("CLIENT_STATIC_DIR", "./client-web"), AdminPassword: env("ADMIN_PASSWORD", "demo-admin-change-me"), CustomerPassword: env("DEMO_CUSTOMER_PASSWORD", "demo-customer")}
	c.PaymentMode = env("PAYMENT_MODE", "mock")
	if c.PaymentMode != "mock" && c.PaymentMode != "real" {
		return c, errors.New("PAYMENT_MODE must be mock or real")
	}
	for _, s := range strings.Split(os.Getenv("CORS_ORIGINS"), ",") {
		if strings.TrimSpace(s) != "" {
			c.Origins = append(c.Origins, strings.TrimSpace(s))
		}
	}
	if c.Environment != "development" && c.Environment != "test" && c.Environment != "production" {
		return c, errors.New("APP_ENV must be development, test or production")
	}
	if c.Environment == "production" {
		minimumPasswordLength := 12
		if os.Getenv("LOCAL_DEBUG_PASSWORDS") == "1" {
			host, _, err := net.SplitHostPort(c.Listen)
			if err == nil && net.ParseIP(host).IsLoopback() {
				minimumPasswordLength = 4
			}
		}
		if utf8.RuneCountInString(c.AdminPassword) < minimumPasswordLength || utf8.RuneCountInString(c.CustomerPassword) < minimumPasswordLength || c.AdminPassword == "demo-admin-change-me" || c.CustomerPassword == "demo-customer" || c.AdminPassword == c.CustomerPassword {
			return c, fmt.Errorf("production requires distinct ADMIN_PASSWORD and DEMO_CUSTOMER_PASSWORD, at least %d characters, and no demo defaults", minimumPasswordLength)
		}
		for _, o := range c.Origins {
			if !strings.HasPrefix(o, "https://") || strings.Contains(o, "*") {
				return c, errors.New("production CORS_ORIGINS must be explicit HTTPS origins")
			}
		}
	}
	if _, _, e := net.SplitHostPort(c.Listen); e != nil {
		return c, fmt.Errorf("LISTEN_ADDR: %w", e)
	}
	return c, nil
}
func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

type credential struct {
	user User
	salt []byte
	hash []byte
}
type session struct {
	user    User
	expires time.Time
}
type loginRate struct {
	count int
	since time.Time
}
type API struct {
	engine       *Engine
	config       Config
	credentials  map[string]credential
	mu           sync.Mutex
	sessions     map[string]session
	rates        map[string]loginRate
	static       http.Handler
	clientStatic http.Handler
}

func NewAPI(engine *Engine, c Config) *API {
	if c.PaymentMode != "" {
		engine.PaymentMode = c.PaymentMode
	}
	a := &API{engine: engine, config: c, credentials: map[string]credential{}, sessions: map[string]session{}, rates: map[string]loginRate{}}
	a.addUser("admin", c.AdminPassword, User{"admin", "运营管理员", "admin"})
	a.addUser("customer", c.CustomerPassword, User{"customer", "客户", "customer"})
	if c.Environment != "production" {
		a.addUser("customer2", c.CustomerPassword, User{"customer2", "第二位客户", "customer"})
	}
	if c.AdminStaticDir != "" {
		a.static = spa(c.AdminStaticDir, "/admin/")
	}
	if c.ClientStaticDir != "" {
		a.clientStatic = spa(c.ClientStaticDir, "/client/")
	}
	return a
}

// Serve only files under the configured root, with index fallback for extensionless routes.
func spa(dir, prefix string) http.Handler {
	root, err := filepath.Abs(dir)
	if err != nil {
		return http.NotFoundHandler()
	}
	if resolved, err := filepath.EvalSymlinks(root); err == nil {
		root = resolved
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, prefix)
		candidate := filepath.Join(root, filepath.FromSlash(name))
		rel, err := filepath.Rel(root, candidate)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			http.NotFound(w, r)
			return
		}
		info, statErr := os.Stat(candidate)
		if statErr == nil && info.IsDir() {
			candidate = filepath.Join(candidate, "index.html")
		}
		if os.IsNotExist(statErr) && filepath.Ext(name) == "" {
			candidate = filepath.Join(root, "index.html")
		}
		resolved, err := filepath.EvalSymlinks(candidate)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		rel, err = filepath.Rel(root, resolved)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			http.NotFound(w, r)
			return
		}
		f, err := os.Open(resolved)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		defer f.Close()
		info, err = f.Stat()
		if err != nil || info.IsDir() {
			http.NotFound(w, r)
			return
		}
		http.ServeContent(w, r, filepath.Base(resolved), info.ModTime(), f)
	})
}
func (a *API) addUser(name, password string, user User) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		panic(err)
	}
	h, err := pbkdf2.Key(sha256.New, password, salt, 210000, 32)
	if err != nil {
		panic(err)
	}
	a.credentials[name] = credential{user, salt, h}
}
func respond(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func fail(w http.ResponseWriter, err error) {
	p := ProblemOf(err)
	if p.Status >= 500 {
		slog.Error("request storage failure", "error", err)
	}
	respond(w, p.Status, map[string]any{"error": map[string]string{"code": p.Code, "message": p.Message}})
}
func decode(w http.ResponseWriter, r *http.Request, out any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 256<<10)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(out); err != nil {
		return invalid("请求正文无效或含未知字段")
	}
	var extra any
	if err := d.Decode(&extra); err != io.EOF {
		return invalid("请求应只包含一个JSON对象")
	}
	return nil
}
func (a *API) authenticate(r *http.Request) (User, error) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if token == "" || token == r.Header.Get("Authorization") {
		return User{}, &Problem{401, "unauthorized", "请先登录"}
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	s, ok := a.sessions[token]
	if !ok || !a.engine.Now().Before(s.expires) {
		delete(a.sessions, token)
		return User{}, &Problem{401, "unauthorized", "登录已失效，请重新登录"}
	}
	return s.user, nil
}
func (a *API) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Account  string `json:"account"`
		Password string `json:"password"`
	}
	if err := decode(w, r, &in); err != nil {
		fail(w, err)
		return
	}
	if len(in.Password) > 512 || len(in.Account) > 100 {
		fail(w, invalid("账号或密码长度无效"))
		return
	}
	now := a.engine.Now()
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	rateKey := host
	a.mu.Lock()
	rate := a.rates[rateKey]
	if now.Sub(rate.since) > time.Minute {
		rate = loginRate{since: now}
	}
	rate.count++
	a.rates[rateKey] = rate
	for k, v := range a.rates {
		if now.Sub(v.since) > 2*time.Minute {
			delete(a.rates, k)
		}
	}
	a.mu.Unlock()
	if rate.count > 10 {
		fail(w, &Problem{429, "rate_limit", "尝试过于频繁，请稍后再试"})
		return
	}
	c, ok := a.credentials[in.Account]
	if !ok {
		c = a.credentials["customer"]
	}
	h, _ := pbkdf2.Key(sha256.New, in.Password, c.salt, 210000, 32)
	if !ok || subtle.ConstantTimeCompare(h, c.hash) != 1 {
		fail(w, &Problem{401, "unauthorized", "账号或密码不正确"})
		return
	}
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		fail(w, err)
		return
	}
	token := hex.EncodeToString(b)
	a.mu.Lock()
	for k, s := range a.sessions {
		if !now.Before(s.expires) {
			delete(a.sessions, k)
		}
	}
	if len(a.sessions) >= 1000 {
		a.mu.Unlock()
		fail(w, &Problem{429, "session_limit", "在线会话过多，请稍后重试"})
		return
	}
	a.sessions[token] = session{c.user, now.Add(8 * time.Hour)}
	a.mu.Unlock()
	respond(w, 200, map[string]any{"token": token, "user": c.user, "expires_at": timestamp(now.Add(8 * time.Hour))})
}
func (a *API) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Cache-Control", "no-store")
	origin := r.Header.Get("Origin")
	if origin != "" {
		allowed := false
		for _, o := range a.config.Origins {
			if o == origin {
				allowed = true
			}
		}
		if !allowed {
			parsed, err := url.Parse(origin)
			loopback := err == nil && (parsed.Hostname() == "localhost" || net.ParseIP(parsed.Hostname()).IsLoopback())
			allowed = err == nil && parsed.Host == r.Host && parsed.User == nil && parsed.Path == "" && parsed.RawQuery == "" && parsed.Fragment == "" && (parsed.Scheme == "https" || parsed.Scheme == "http" && (a.config.Environment != "production" || loopback))
		}
		if !allowed {
			fail(w, denied())
			return
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Add("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Idempotency-Key")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
	}
	if r.Method == "OPTIONS" {
		w.WriteHeader(204)
		return
	}
	if (r.URL.Path == "/healthz" || r.URL.Path == "/api/v1/health") && r.Method == "GET" {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := a.engine.Store.View(ctx, func(s *State) error { return nil }); err != nil {
			fail(w, err)
			return
		}
		respond(w, 200, map[string]any{"status": "ok", "version": "0.2.0", "environment": a.config.Environment, "payment_mode": a.engine.PaymentMode})
		return
	}
	if r.URL.Path == "/" && r.Method == "GET" {
		http.Redirect(w, r, "/admin/", http.StatusTemporaryRedirect)
		return
	}
	if r.URL.Path == "/admin" {
		http.Redirect(w, r, "/admin/", http.StatusTemporaryRedirect)
		return
	}
	if r.URL.Path == "/client" {
		http.Redirect(w, r, "/client/", http.StatusTemporaryRedirect)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/client/") && r.Method == "GET" {
		if a.clientStatic == nil {
			http.NotFound(w, r)
			return
		}
		a.clientStatic.ServeHTTP(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/admin/") && r.Method == "GET" {
		if a.static == nil {
			http.NotFound(w, r)
			return
		}
		a.static.ServeHTTP(w, r)
		return
	}
	if r.URL.Path == "/api/v1/auth/login" && r.Method == "POST" {
		a.login(w, r)
		return
	}
	if r.URL.Path == "/api/v1/services" && r.Method == "GET" {
		s, err := a.engine.Services(r.Context())
		if err != nil {
			fail(w, err)
			return
		}
		respond(w, 200, map[string]any{"services": s})
		return
	}
	if a.publicShop(w, r) {
		return
	}
	u, err := a.authenticate(r)
	if err != nil {
		fail(w, err)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	if a.privateShop(w, r, ctx, u) {
		return
	}
	if r.URL.Path == "/api/v1/auth/logout" && r.Method == "POST" {
		a.mu.Lock()
		delete(a.sessions, strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		a.mu.Unlock()
		respond(w, 200, map[string]bool{"ok": true})
		return
	}
	if r.URL.Path == "/api/v1/workspace" && r.Method == "GET" {
		cases, err := a.engine.Cases(ctx, u)
		if err != nil {
			fail(w, err)
			return
		}
		services, err := a.engine.Services(ctx)
		if err != nil {
			fail(w, err)
			return
		}
		respond(w, 200, map[string]any{"user": u, "services": services, "cases": cases})
		return
	}
	if r.URL.Path == "/api/v1/cases" && r.Method == "POST" {
		var in CreateInput
		if err := decode(w, r, &in); err != nil {
			fail(w, err)
			return
		}
		c, err := a.engine.Create(ctx, u, r.Header.Get("Idempotency-Key"), in)
		if err != nil {
			fail(w, err)
			return
		}
		respond(w, 201, map[string]any{"case": c})
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/operations/") && r.Method == "GET" {
		key := strings.TrimPrefix(r.URL.Path, "/api/v1/operations/")
		c, receipt, err := a.engine.Operation(ctx, u, key)
		if err != nil {
			fail(w, err)
			return
		}
		respond(w, 200, map[string]any{"operation": map[string]any{"status": "succeeded", "case_id": receipt.CaseID, "action": receipt.Action, "created_at": receipt.Created}, "case": c})
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/v1/cases/"), "/")
	if strings.HasPrefix(r.URL.Path, "/api/v1/cases/") && len(parts) >= 1 {
		id := parts[0]
		if len(parts) == 1 && r.Method == "GET" {
			c, err := a.engine.Get(ctx, u, id)
			if err != nil {
				fail(w, err)
				return
			}
			respond(w, 200, map[string]any{"case": c})
			return
		}
		if len(parts) == 2 && parts[1] == "actions" && r.Method == "POST" {
			var in Action
			if err := decode(w, r, &in); err != nil {
				fail(w, err)
				return
			}
			c, err := a.engine.Act(ctx, u, id, r.Header.Get("Idempotency-Key"), in)
			if err != nil {
				fail(w, err)
				return
			}
			respond(w, 200, map[string]any{"case": c})
			return
		}
		if len(parts) == 2 && parts[1] == "attachments" && r.Method == "POST" {
			a.upload(w, r, ctx, u, id)
			return
		}
		if len(parts) == 3 && parts[1] == "attachments" && r.Method == "GET" {
			file, err := a.engine.Download(ctx, u, id, parts[2])
			if err != nil {
				fail(w, err)
				return
			}
			w.Header().Set("Content-Type", "application/octet-stream")
			w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": file.Name}))
			w.Header().Set("Content-Length", strconv.Itoa(file.Size))
			w.Header().Set("Content-Security-Policy", "sandbox")
			w.WriteHeader(200)
			_, _ = w.Write(file.Data)
			return
		}
	}
	if r.URL.Path == "/api/v1/admin/outbox" && r.Method == "GET" {
		if u.Role != "admin" {
			fail(w, denied())
			return
		}
		var out []Notice
		err := a.engine.Store.View(ctx, func(s *State) error { out = append([]Notice{}, s.Outbox...); return nil })
		if err != nil {
			fail(w, err)
			return
		}
		respond(w, 200, map[string]any{"notifications": out, "delivery_enabled": false})
		return
	}
	fail(w, missing())
}
func (a *API) upload(w http.ResponseWriter, r *http.Request, ctx context.Context, u User, id string) {
	r.Body = http.MaxBytesReader(w, r.Body, 9<<20)
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		fail(w, invalid("上传表单无效或超过8MB"))
		return
	}
	if r.MultipartForm != nil {
		defer r.MultipartForm.RemoveAll()
	}
	f, fh, err := r.FormFile("file")
	if err != nil {
		fail(w, invalid("缺少file文件"))
		return
	}
	defer f.Close()
	if len(r.MultipartForm.File["file"]) != 1 {
		fail(w, invalid("每次只上传一个文件"))
		return
	}
	v, err := strconv.Atoi(r.FormValue("expected_version"))
	if err != nil {
		fail(w, invalid("缺少有效expected_version"))
		return
	}
	b, err := io.ReadAll(io.LimitReader(f, 8<<20+1))
	if err != nil {
		fail(w, err)
		return
	}
	name := filepath.Base(fh.Filename)
	c, err := a.engine.Upload(ctx, u, id, r.Header.Get("Idempotency-Key"), v, name, http.DetectContentType(b), b)
	if err != nil {
		fail(w, err)
		return
	}
	respond(w, 201, map[string]any{"case": c})
}
