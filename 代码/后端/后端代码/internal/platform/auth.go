// Created by Jobs on 2026年11月6日，星期五.
package platform

import (
	"bytes"
	"context"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math/big"
	"net"
	"net/http"
	"net/mail"
	"net/smtp"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// Accounts live in the same atomic store as orders; password material is never returned.
type Account struct {
	User User   `json:"user"`
	Salt []byte `json:"salt"`
	Hash []byte `json:"password_hash"`
}
type emailChallenge struct {
	digest   [32]byte
	sent     time.Time
	expires  time.Time
	attempts int
}

func randomAvatar() string {
	var seed [4]byte
	if _, err := rand.Read(seed[:]); err != nil {
		panic(err)
	}
	img := image.NewRGBA(image.Rect(0, 0, 64, 64))
	foreground := color.RGBA{40 + seed[0]%150, 40 + seed[1]%150, 40 + seed[2]%150, 255}
	for y := 0; y < 64; y++ {
		for x := 0; x < 64; x++ {
			shade := color.RGBA{235, 239, 245, 255}
			column := x / 12
			if column > 2 {
				column = 4 - column
			}
			if column >= 0 && seed[(y/12+column)%4]&(1<<uint((y/12+column)%8)) != 0 {
				shade = foreground
			}
			img.SetRGBA(x, y, shade)
		}
	}
	var out bytes.Buffer
	_ = png.Encode(&out, img)
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(out.Bytes())
}
func credentialAccount(c credential) Account {
	return Account{User: c.user, Salt: c.salt, Hash: c.hash}
}
func (a *API) allAccounts(s *State) map[string]Account {
	result := map[string]Account{}
	for _, c := range a.credentials {
		result[c.user.ID] = credentialAccount(c)
	}
	for id, c := range s.Accounts {
		// Seed credentials belong to the active deployment, even after a Demo profile edit.
		if seed, ok := result[id]; ok {
			c.Salt, c.Hash = seed.Salt, seed.Hash
		}
		result[id] = c
	}
	return result
}
func (a *API) findCredential(ctx context.Context, name string) (credential, bool, error) {
	var found credential
	ok := false
	name = strings.TrimSpace(name)
	err := a.engine.Store.View(ctx, func(s *State) error {
		accounts := a.allAccounts(s)
		if a.config.DemoMode && strings.EqualFold(name, "admin") {
			c := accounts["admin"]
			found, ok = credential{c.User, c.Salt, c.Hash}, true
			return nil
		}
		for _, c := range accounts {
			if strings.EqualFold(c.User.Username, name) || c.User.Email != "" && strings.EqualFold(c.User.Email, name) {
				found = credential{c.User, c.Salt, c.Hash}
				ok = true
				break
			}
		}
		return nil
	})
	return found, ok, err
}
func normalizedEmail(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	parsed, err := mail.ParseAddress(value)
	if err != nil || parsed.Address != value || len(value) > 254 || !strings.Contains(value, "@") || strings.ContainsAny(value, "\r\n") {
		return "", invalid("请输入有效邮箱地址")
	}
	return value, nil
}
func validUsername(value string) bool {
	n := utf8.RuneCountInString(value)
	if n < 3 || n > 32 {
		return false
	}
	for _, r := range value {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' && r != '-' {
			return false
		}
	}
	return true
}
func validPassword(password, confirmation string) error {
	if password != confirmation {
		return invalid("两次输入的密码不一致")
	}
	if utf8.RuneCountInString(password) < 8 || len(password) > 512 {
		return invalid("密码至少8个字符，最多512字节")
	}
	return nil
}
func newAccount(user User, password string) Account {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		panic(err)
	}
	derived, err := pbkdf2.Key(sha256.New, password, salt, 210000, 32)
	if err != nil {
		panic(err)
	}
	return Account{user, salt, derived}
}
func challengeDigest(email, purpose, code string) [32]byte {
	return sha256.Sum256([]byte(email + "\x00" + purpose + "\x00" + code))
}
func (a *API) publicAuth(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != "POST" {
		return false
	}
	switch r.URL.Path {
	case "/api/v1/auth/email-code":
		a.requestEmailCode(w, r)
	case "/api/v1/auth/register":
		a.registerAccount(w, r, false)
	case "/api/v1/auth/reset-password":
		a.registerAccount(w, r, true)
	default:
		return false
	}
	return true
}
func (a *API) requestEmailCode(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email   string `json:"email"`
		Purpose string `json:"purpose"`
	}
	if err := decode(w, r, &in); err != nil {
		fail(w, err)
		return
	}
	email, err := normalizedEmail(in.Email)
	if err != nil {
		fail(w, err)
		return
	}
	if in.Purpose != "register" && in.Purpose != "reset_password" {
		fail(w, invalid("验证码用途无效"))
		return
	}
	now := a.engine.Now()
	key := email + ":" + in.Purpose
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	a.mu.Lock()
	for k, c := range a.emailCodes {
		if !now.Before(c.expires) {
			delete(a.emailCodes, k)
		}
	}
	rate := a.emailRates[host]
	if now.Sub(rate.since) > 10*time.Minute {
		rate = loginRate{since: now}
	}
	rate.count++
	a.emailRates[host] = rate
	for k, v := range a.emailRates {
		if now.Sub(v.since) > 20*time.Minute {
			delete(a.emailRates, k)
		}
	}
	prior, exists := a.emailCodes[key]
	if rate.count > 20 || len(a.emailCodes) >= 1000 || exists && now.Sub(prior.sent) < time.Minute {
		a.mu.Unlock()
		fail(w, &Problem{429, "rate_limit", "验证码发送过于频繁，请稍后再试"})
		return
	}
	number, randomErr := rand.Int(rand.Reader, big.NewInt(1000000))
	if randomErr != nil {
		a.mu.Unlock()
		fail(w, randomErr)
		return
	}
	code := fmt.Sprintf("%06d", number.Int64())
	challenge := emailChallenge{digest: challengeDigest(email, in.Purpose, code), sent: now, expires: now.Add(10 * time.Minute)}
	a.emailCodes[key] = challenge
	a.mu.Unlock()
	demoDelivery := a.config.DemoMode && a.config.SMTPHost == ""
	if !demoDelivery {
		err = a.sendEmail(r.Context(), email, in.Purpose, code)
	}
	if err != nil {
		a.mu.Lock()
		if a.emailCodes[key].digest == challenge.digest {
			delete(a.emailCodes, key)
		}
		a.mu.Unlock()
		// Never log recipient, verification code, SMTP credentials or transport error text.
		fail(w, &Problem{503, "email_unavailable", "邮件服务暂不可用，请稍后重试"})
		return
	}
	out := map[string]any{"ok": true, "expires_in": 600, "retry_after": 60, "delivery": "email"}
	if demoDelivery {
		out["delivery"] = "demo"
		out["demo_code"] = code
	}
	respond(w, 200, out)
}
func (a *API) registerAccount(w http.ResponseWriter, r *http.Request, reset bool) {
	var in struct {
		Email           string `json:"email"`
		Code            string `json:"code"`
		Username        string `json:"username"`
		Password        string `json:"password"`
		ConfirmPassword string `json:"confirm_password"`
	}
	if err := decode(w, r, &in); err != nil {
		fail(w, err)
		return
	}
	email, err := normalizedEmail(in.Email)
	if err != nil {
		fail(w, err)
		return
	}
	in.Username = strings.TrimSpace(in.Username)
	if !reset && !validUsername(in.Username) {
		fail(w, invalid("用户名须为3至32个字母、汉字、数字、下划线或短横线"))
		return
	}
	if err = validPassword(in.Password, in.ConfirmPassword); err != nil {
		fail(w, err)
		return
	}
	purpose := "register"
	if reset {
		purpose = "reset_password"
	}
	key := email + ":" + purpose
	now := a.engine.Now()
	a.mu.Lock()
	defer a.mu.Unlock()
	challenge, exists := a.emailCodes[key]
	digest := challengeDigest(email, purpose, in.Code)
	if !exists || !now.Before(challenge.expires) || challenge.attempts >= 5 || len(in.Code) != 6 || subtle.ConstantTimeCompare(digest[:], challenge.digest[:]) != 1 {
		if exists {
			challenge.attempts++
			a.emailCodes[key] = challenge
		}
		fail(w, invalid("邮箱验证码无效或已过期"))
		return
	}
	var saved Account
	// Consume the verified code only after the atomic account write succeeds.
	err = a.engine.Store.Update(r.Context(), func(s *State) error {
		all := a.allAccounts(s)
		var existing *Account
		for _, c := range all {
			if c.User.Email == email {
				row := c
				existing = &row
			}
		}
		if reset {
			if existing == nil {
				return invalid("邮箱验证码无效或账户不可用")
			}
			saved = newAccount(existing.User, in.Password)
		} else {
			if existing != nil {
				return &Problem{409, "account_exists", "邮箱已注册，请登录或找回密码"}
			}
			if _, reserved := a.credentials[strings.ToLower(in.Username)]; reserved {
				return &Problem{409, "username_taken", "用户名已被使用"}
			}
			for _, c := range all {
				if strings.EqualFold(c.User.Username, in.Username) {
					return &Problem{409, "username_taken", "用户名已被使用"}
				}
			}
			saved = newAccount(User{ID: uuid(), Name: in.Username, Username: in.Username, Email: email, Role: "customer", AvatarURL: randomAvatar()}, in.Password)
		}
		if s.Accounts == nil {
			s.Accounts = map[string]Account{}
		}
		s.Accounts[saved.User.ID] = saved
		return nil
	})
	if err != nil {
		fail(w, err)
		return
	}
	delete(a.emailCodes, key)
	if reset {
		for token, session := range a.sessions {
			if session.user.ID == saved.User.ID {
				delete(a.sessions, token)
			}
		}
	}
	respond(w, 200, map[string]any{"ok": true, "user": saved.User})
}
func (a *API) privateAuth(w http.ResponseWriter, r *http.Request, ctx context.Context, u User) bool {
	if r.URL.Path != "/api/v1/auth/profile" {
		return false
	}
	if r.Method == "GET" {
		respond(w, 200, map[string]any{"user": u})
		return true
	}
	if r.Method != "PUT" {
		return false
	}
	var in struct {
		Username string  `json:"username"`
		Avatar   *string `json:"avatar"`
	}
	if err := decodeLimit(w, r, &in, 3<<20); err != nil {
		fail(w, err)
		return true
	}
	in.Username = strings.TrimSpace(in.Username)
	if !validUsername(in.Username) {
		fail(w, invalid("用户名须为3至32个字母、汉字、数字、下划线或短横线"))
		return true
	}
	if in.Avatar != nil && *in.Avatar != "" {
		if !strings.HasPrefix(*in.Avatar, "data:image/") {
			fail(w, invalid("请上传PNG、JPEG或WebP头像"))
			return true
		}
		if err := validShopImage(*in.Avatar, 2<<20, false); err != nil {
			fail(w, err)
			return true
		}
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	err := a.engine.Store.Update(ctx, func(s *State) error {
		all := a.allAccounts(s)
		current, ok := all[u.ID]
		if !ok {
			return missing()
		}
		if seed, reserved := a.credentials[strings.ToLower(in.Username)]; reserved && seed.user.ID != u.ID {
			return &Problem{409, "username_taken", "用户名已被使用"}
		}
		for id, c := range all {
			if id != u.ID && strings.EqualFold(c.User.Username, in.Username) {
				return &Problem{409, "username_taken", "用户名已被使用"}
			}
		}
		current.User.Username = in.Username
		current.User.Name = in.Username
		if in.Avatar != nil {
			current.User.AvatarURL = *in.Avatar
			if *in.Avatar == "" {
				current.User.AvatarURL = randomAvatar()
			}
		}
		if s.Accounts == nil {
			s.Accounts = map[string]Account{}
		}
		s.Accounts[u.ID] = current
		u = current.User
		return nil
	})
	if err != nil {
		fail(w, err)
		return true
	}
	for token, current := range a.sessions {
		if current.user.ID == u.ID {
			current.user = u
			a.sessions[token] = current
		}
	}
	respond(w, 200, map[string]any{"user": u})
	return true
}
func (a *API) deliverEmail(ctx context.Context, to, purpose, code string) error {
	c := a.config
	if c.SMTPHost == "" || c.SMTPFrom == "" {
		return fmt.Errorf("SMTP configuration unavailable")
	}
	from, err := mail.ParseAddress(c.SMTPFrom)
	if err != nil || strings.ContainsAny(c.SMTPFrom, "\r\n") {
		return fmt.Errorf("invalid sender")
	}
	address := net.JoinHostPort(c.SMTPHost, c.SMTPPort)
	dialer := net.Dialer{Timeout: 6 * time.Second}
	var conn net.Conn
	if c.SMTPTLSMode == "implicit" {
		conn, err = (&tls.Dialer{NetDialer: &dialer, Config: &tls.Config{ServerName: c.SMTPHost, MinVersion: tls.VersionTLS12}}).DialContext(ctx, "tcp", address)
	} else {
		conn, err = dialer.DialContext(ctx, "tcp", address)
	}
	if err != nil {
		return err
	}
	defer conn.Close()
	deadline := time.Now().Add(10 * time.Second)
	if requestDeadline, ok := ctx.Deadline(); ok && requestDeadline.Before(deadline) {
		deadline = requestDeadline
	}
	_ = conn.SetDeadline(deadline)
	client, err := smtp.NewClient(conn, c.SMTPHost)
	if err != nil {
		return err
	}
	defer client.Close()
	if c.SMTPTLSMode != "implicit" {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return fmt.Errorf("SMTP requires TLS")
		}
		if err = client.StartTLS(&tls.Config{ServerName: c.SMTPHost, MinVersion: tls.VersionTLS12}); err != nil {
			return err
		}
	}
	if c.SMTPUsername != "" {
		if err = client.Auth(smtp.PlainAuth("", c.SMTPUsername, c.SMTPPassword, c.SMTPHost)); err != nil {
			return err
		}
	}
	if err = client.Mail(from.Address); err != nil {
		return err
	}
	if err = client.Rcpt(to); err != nil {
		return err
	}
	body, err := client.Data()
	if err != nil {
		return err
	}
	_, err = fmt.Fprintf(body, "From: %s\r\nTo: %s\r\nSubject: Zhixu verification code\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nYour %s verification code is %s. It expires in 10 minutes.\r\n", from.Address, to, purpose, code)
	if err != nil {
		_ = body.Close()
		return err
	}
	if err = body.Close(); err != nil {
		return err
	}
	return client.Quit()
}
