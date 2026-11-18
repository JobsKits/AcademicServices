// Created by Jobs on 2026年11月6日，星期五.
package platform

import (
	"bytes"
	"context"
	"encoding/base64"
	"image"
	"image/color"
	"image/gif"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func authTestSetup(t *testing.T, demo bool) (*API, *httptest.Server) {
	t.Helper()
	api := NewAPI(NewEngine(NewMemoryStore()), Config{Environment: "test", DemoMode: demo, AdminPassword: "formal-admin-password", CustomerPassword: "formal-customer-password"})
	server := httptest.NewServer(api)
	t.Cleanup(server.Close)
	return api, server
}
func authCode(t *testing.T, s *httptest.Server, email, purpose string) string {
	t.Helper()
	status, out := request(t, s, "POST", "/api/v1/auth/email-code", "", "", map[string]string{"email": email, "purpose": purpose})
	if status != 200 {
		t.Fatalf("code: %d %v", status, out)
	}
	return out["demo_code"].(string)
}
func createEmailAccount(t *testing.T, s *httptest.Server, email, name string) {
	t.Helper()
	code := authCode(t, s, email, "register")
	status, out := request(t, s, "POST", "/api/v1/auth/register", "", "", map[string]string{"email": email, "code": code, "username": name, "password": "password-original", "confirm_password": "password-original"})
	if status != 200 {
		t.Fatalf("register: %d %v", status, out)
	}
}
func accountToken(t *testing.T, s *httptest.Server, account, password string) (string, map[string]any) {
	t.Helper()
	status, out := request(t, s, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": account, "password": password})
	if status != 200 {
		t.Fatalf("login: %d %v", status, out)
	}
	return out["token"].(string), out["user"].(map[string]any)
}
func TestEmailRegistrationLoginProfileResetAndReplay(t *testing.T) {
	_, server := authTestSetup(t, true)
	email := "chen@example.test"
	createEmailAccount(t, server, email, "泉羽用户")
	token, user := accountToken(t, server, strings.ToUpper(email), "password-original")
	if user["email"] != email || user["username"] != "泉羽用户" || !strings.HasPrefix(user["avatar_url"].(string), "data:image/png;base64,") {
		t.Fatal(user)
	}
	accountToken(t, server, "泉羽用户", "password-original")
	status, out := request(t, server, "PUT", "/api/v1/auth/profile", token, "", map[string]any{"username": "更改用户名", "avatar": user["avatar_url"]})
	if status != 200 || out["user"].(map[string]any)["name"] != "更改用户名" {
		t.Fatal(status, out)
	}
	accountToken(t, server, "更改用户名", "password-original")
	status, _ = request(t, server, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": "泉羽用户", "password": "password-original"})
	if status != 401 {
		t.Fatal("old username still accepted")
	}
	code := authCode(t, server, email, "reset_password")
	body := map[string]string{"email": email, "code": code, "password": "password-replaced", "confirm_password": "password-replaced"}
	status, out = request(t, server, "POST", "/api/v1/auth/reset-password", "", "", body)
	if status != 200 {
		t.Fatal(status, out)
	}
	status, _ = request(t, server, "GET", "/api/v1/shop-orders", token, "", nil)
	if status != 401 {
		t.Fatal("reset retained session")
	}
	accountToken(t, server, email, "password-replaced")
	status, _ = request(t, server, "POST", "/api/v1/auth/reset-password", "", "", body)
	if status != 422 {
		t.Fatal("verification code replayed", status)
	}
}
func TestVerificationExpiryAttemptLimitAndPurpose(t *testing.T) {
	api, server := authTestSetup(t, true)
	email := "limit@example.test"
	code := authCode(t, server, email, "register")
	body := map[string]string{"email": email, "code": code, "username": "test-limit", "password": "password-original", "confirm_password": "password-original"}
	status, _ := request(t, server, "POST", "/api/v1/auth/reset-password", "", "", body)
	if status != 422 {
		t.Fatal("purpose not isolated")
	}
	wrong := "000000"
	if code == wrong {
		wrong = "111111"
	}
	body["code"] = wrong
	for range 5 {
		status, _ = request(t, server, "POST", "/api/v1/auth/register", "", "", body)
		if status != 422 {
			t.Fatal(status)
		}
	}
	body["code"] = code
	status, _ = request(t, server, "POST", "/api/v1/auth/register", "", "", body)
	if status != 422 {
		t.Fatal("attempt limit bypassed")
	}
	api.engine.Now = func() time.Time { return time.Now().Add(11 * time.Minute) }
	status, _ = request(t, server, "POST", "/api/v1/auth/register", "", "", body)
	if status != 422 {
		t.Fatal("expired code accepted")
	}
}
func TestFormalEmailUnavailableNeverReturnsDemoCodeAndAdminIsProtected(t *testing.T) {
	_, server := authTestSetup(t, false)
	status, out := request(t, server, "POST", "/api/v1/auth/email-code", "", "", map[string]string{"email": "formal@example.test", "purpose": "register"})
	if status != 503 || out["demo_code"] != nil {
		t.Fatal(status, out)
	}
	status, _ = request(t, server, "GET", "/api/v1/admin/products", "", "", nil)
	if status != 401 {
		t.Fatal("formal admin publicly accessible")
	}
	status, _ = request(t, server, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": "admin", "password": "1234"})
	if status != 401 {
		t.Fatal("demo password accepted in formal")
	}
}
func TestDemoAdminUses1234AndPublicConfigMatches(t *testing.T) {
	_, server := authTestSetup(t, true)
	_, user := accountToken(t, server, "admin", "1234")
	if user["role"] != "admin" {
		t.Fatal(user)
	}
	status, out := request(t, server, "GET", "/api/v1/shop-config", "", "", nil)
	if status != 200 || out["demo_credentials"].([]any)[1].(map[string]any)["password"] != "1234" {
		t.Fatal(status, out)
	}
}
func TestFormalEmailDeliveryUsesSenderWithoutDisclosure(t *testing.T) {
	api, server := authTestSetup(t, false)
	var received string
	api.sendEmail = func(ctx context.Context, to, purpose, code string) error {
		if to != "mail@example.test" || purpose != "register" || len(code) != 6 {
			t.Fatal(to, purpose)
		}
		received = code
		return nil
	}
	status, out := request(t, server, "POST", "/api/v1/auth/email-code", "", "", map[string]string{"email": "mail@example.test", "purpose": "register"})
	if status != 200 || out["delivery"] != "email" || out["demo_code"] != nil || received == "" {
		t.Fatal(status, out)
	}
	status, out = request(t, server, "POST", "/api/v1/auth/register", "", "", map[string]string{"email": "mail@example.test", "code": received, "username": "email-user", "password": "password-original", "confirm_password": "password-original"})
	if status != 200 {
		t.Fatal(status, out)
	}
}
func TestAccountFilePersistenceAndAvatarRestrictions(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	api := NewAPI(NewEngine(store), Config{Environment: "test", DemoMode: true, CustomerPassword: "customer-secret"})
	server := httptest.NewServer(api)
	createEmailAccount(t, server, "persist@example.test", "persistent-user")
	token, _ := accountToken(t, server, "persist@example.test", "password-original")
	for _, avatar := range []string{"javascript:alert(1)", "https://example.test/avatar.png", "data:image/svg+xml;base64,PHN2Zy8+"} {
		status, _ := request(t, server, "PUT", "/api/v1/auth/profile", token, "", map[string]string{"username": "persistent-user", "avatar": avatar})
		if status != 422 {
			t.Fatal("unsafe avatar accepted", status)
		}
	}
	server.Close()
	store.Close()
	store, err = OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(store.Close)
	restored := httptest.NewServer(NewAPI(NewEngine(store), Config{Environment: "test", CustomerPassword: "customer-secret"}))
	t.Cleanup(restored.Close)
	accountToken(t, restored, "persist@example.test", "password-original")
}

func TestDemoProfileCannotPersistWeakAdminPasswordIntoFormal(t *testing.T) {
	store := NewMemoryStore()
	demo := httptest.NewServer(NewAPI(NewEngine(store), Config{Environment: "test", DemoMode: true, CustomerPassword: "customer-secret"}))
	token, _ := accountToken(t, demo, "admin", "1234")
	status, out := request(t, demo, "PUT", "/api/v1/auth/profile", token, "", map[string]string{"username": "my-admin"})
	if status != 200 {
		t.Fatal(status, out)
	}
	accountToken(t, demo, "admin", "1234")
	createEmailAccount(t, demo, "reserved-name@example.test", "other-user")
	other, _ := accountToken(t, demo, "other-user", "password-original")
	status, _ = request(t, demo, "PUT", "/api/v1/auth/profile", other, "", map[string]string{"username": "admin"})
	if status != 409 {
		t.Fatal("reserved admin alias was reassigned", status)
	}
	demo.Close()
	formal := httptest.NewServer(NewAPI(NewEngine(store), Config{Environment: "test", AdminPassword: "formal-strong-password", CustomerPassword: "customer-secret"}))
	defer formal.Close()
	status, _ = request(t, formal, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": "my-admin", "password": "1234"})
	if status != 401 {
		t.Fatal("Demo password leaked into formal credentials", status)
	}
	accountToken(t, formal, "my-admin", "formal-strong-password")
}

func TestProfilePartialEditsPreserveUIDAndVerifiedRecoveryAfterRestart(t *testing.T) {
	dir := t.TempDir()
	var store *FileStore
	var server *httptest.Server
	restart := func() {
		t.Helper()
		if server != nil {
			server.Close()
			server = nil
		}
		if store != nil {
			store.Close()
			store = nil
		}
		var err error
		store, err = OpenFileStore(dir)
		if err != nil {
			t.Fatalf("reopen profile store: %v", err)
		}
		server = httptest.NewServer(NewAPI(NewEngine(store), Config{Environment: "test", DemoMode: true, CustomerPassword: "customer-secret"}))
	}
	t.Cleanup(func() {
		if server != nil {
			server.Close()
		}
		if store != nil {
			store.Close()
		}
	})
	restart()
	verified := "verified-profile@example.test"
	createEmailAccount(t, server, verified, "profile-owner")
	token, original := accountToken(t, server, verified, "password-original")
	uid := original["id"]
	mood := "  慢慢来，每一步都算数。\n"
	status, out := request(t, server, "PUT", "/api/v1/auth/profile", token, "", map[string]string{"mood": mood})
	if status != 200 {
		t.Fatal("partial mood requires no username", status, out)
	}
	user := out["user"].(map[string]any)
	if user["id"] != uid || user["username"] != original["username"] || user["avatar_url"] != original["avatar_url"] || user["mood"] != mood {
		t.Fatal("partial update lost unchanged fields", user)
	}
	for _, field := range []string{"id", "uid"} {
		status, out = request(t, server, "PUT", "/api/v1/auth/profile", token, "", map[string]string{field: "client-controlled-id", "mood": "must-not-commit"})
		if status != 422 {
			t.Fatal("client supplied system UID was accepted", field, status, out)
		}
	}
	// Contact fields are display data: preserve invalid text, whitespace and explicit clears.
	for _, contact := range []struct{ email, phone string }{
		{"  不是邮箱 / keep spaces\t", "  +86 任意号码  "},
		{"", ""},
		{"unverified-profile@example.test", "  010-ABCD / 123  "},
	} {
		status, out = request(t, server, "PUT", "/api/v1/auth/profile", token, "", map[string]string{"email": contact.email, "phone": contact.phone})
		if status != 200 {
			t.Fatal("unverified contact rejected", status, out)
		}
		user = out["user"].(map[string]any)
		if email, _ := user["email"].(string); email != contact.email {
			t.Fatalf("email changed: got %q want %q", email, contact.email)
		}
		if phone, _ := user["phone"].(string); phone != contact.phone {
			t.Fatalf("phone changed: got %q want %q", phone, contact.phone)
		}
		restart()
		token, user = accountToken(t, server, verified, "password-original")
		if user["id"] != uid || user["mood"] != mood || user["username"] != original["username"] {
			t.Fatal("profile identity changed after restart", user)
		}
		if email, _ := user["email"].(string); email != contact.email {
			t.Fatal("email was not persisted verbatim", user)
		}
		if phone, _ := user["phone"].(string); phone != contact.phone {
			t.Fatal("phone was not persisted verbatim", user)
		}
	}
	unverified := "unverified-profile@example.test"
	status, _ = request(t, server, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": unverified, "password": "password-original"})
	if status != 401 {
		t.Fatal("unverified display email became login identity", status)
	}
	code := authCode(t, server, unverified, "reset_password")
	status, out = request(t, server, "POST", "/api/v1/auth/reset-password", "", "", map[string]string{"email": unverified, "code": code, "password": "password-stolen", "confirm_password": "password-stolen"})
	if status != 422 {
		t.Fatal("unverified display email acquired recovery rights", status, out)
	}
	code = authCode(t, server, verified, "reset_password")
	status, out = request(t, server, "POST", "/api/v1/auth/reset-password", "", "", map[string]string{"email": verified, "code": code, "password": "password-replaced", "confirm_password": "password-replaced"})
	if status != 200 {
		t.Fatal("original verified email lost recovery rights", status, out)
	}
	status, _ = request(t, server, "GET", "/api/v1/auth/profile", token, "", nil)
	if status != 401 {
		t.Fatal("password reset retained prior session", status)
	}
	restart()
	_, user = accountToken(t, server, verified, "password-replaced")
	if user["id"] != uid || user["email"] != unverified || user["mood"] != mood {
		t.Fatal("reset or restart changed display data or UID", user)
	}
	status, _ = request(t, server, "POST", "/api/v1/auth/login", "", "", map[string]string{"account": unverified, "password": "password-replaced"})
	if status != 401 {
		t.Fatal("reset promoted display email into login identity", status)
	}
	code = authCode(t, server, unverified, "reset_password")
	status, _ = request(t, server, "POST", "/api/v1/auth/reset-password", "", "", map[string]string{"email": unverified, "code": code, "password": "password-stolen", "confirm_password": "password-stolen"})
	if status != 422 {
		t.Fatal("reset promoted display email into recovery identity", status)
	}
}

func TestProfileAnimatedGIFPersistsAndRejectsMismatchedMIME(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(NewAPI(NewEngine(store), Config{Environment: "test", DemoMode: true, CustomerPassword: "customer-secret"}))
	createEmailAccount(t, server, "gif-avatar@example.test", "gif-avatar-owner")
	token, original := accountToken(t, server, "gif-avatar@example.test", "password-original")
	palette := color.Palette{color.White, color.Black}
	first := image.NewPaletted(image.Rect(0, 0, 2, 2), palette)
	second := image.NewPaletted(image.Rect(0, 0, 2, 2), palette)
	second.SetColorIndex(0, 0, 1)
	var encoded bytes.Buffer
	if err = gif.EncodeAll(&encoded, &gif.GIF{Image: []*image.Paletted{first, second}, Delay: []int{10, 10}, LoopCount: 0}); err != nil {
		t.Fatal(err)
	}
	avatar := "data:image/gif;base64," + base64.StdEncoding.EncodeToString(encoded.Bytes())
	status, out := request(t, server, "PUT", "/api/v1/auth/profile", token, "", map[string]string{"avatar": avatar})
	if status != 200 || out["user"].(map[string]any)["avatar_url"] != avatar {
		t.Fatal("animated GIF not preserved", status, out)
	}
	for _, invalidAvatar := range []string{
		strings.Replace(avatar, "image/gif", "image/png", 1),
		strings.Replace(original["avatar_url"].(string), "image/png", "image/gif", 1),
		"data:image/gif;base64,not-base64!",
	} {
		status, out = request(t, server, "PUT", "/api/v1/auth/profile", token, "", map[string]string{"avatar": invalidAvatar})
		if status != 422 {
			t.Fatal("mismatched or invalid image accepted", status, out)
		}
	}
	server.Close()
	store.Close()
	store, err = OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(store.Close)
	server = httptest.NewServer(NewAPI(NewEngine(store), Config{Environment: "test", DemoMode: true, CustomerPassword: "customer-secret"}))
	t.Cleanup(server.Close)
	_, user := accountToken(t, server, "gif-avatar@example.test", "password-original")
	if user["avatar_url"] != avatar {
		t.Fatal("GIF changed after persistence or rejected update")
	}
	data, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(user["avatar_url"].(string), "data:image/gif;base64,"))
	if err != nil {
		t.Fatal(err)
	}
	animation, err := gif.DecodeAll(bytes.NewReader(data))
	if err != nil || len(animation.Image) != 2 || animation.Delay[0] != 10 || animation.Delay[1] != 10 {
		t.Fatal("avatar animation frames or timing were lost", animation, err)
	}
}
