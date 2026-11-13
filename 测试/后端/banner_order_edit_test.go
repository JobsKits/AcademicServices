// Created by Jobs on 2026年11月5日，星期四.
package platform

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

func bannerFixture(t *testing.T) BannerInput {
	t.Helper()
	var buffer bytes.Buffer
	picture := image.NewRGBA(image.Rect(0, 0, 2, 2))
	picture.Set(0, 0, color.RGBA{R: 200, G: 130, B: 70, A: 255})
	if err := png.Encode(&buffer, picture); err != nil {
		t.Fatal(err)
	}
	return BannerInput{Title: "课程与服务", Image: "data:image/png;base64," + base64.StdEncoding.EncodeToString(buffer.Bytes()), TargetURL: "https://example.org/course", Active: true, SortOrder: 1}
}
func TestBannerDefaultsAndAdminVersionedPersistence(t *testing.T) {
	e := NewEngine(NewMemoryStore())
	defaults, err := e.Banners(testCtx, false)
	if err != nil || len(defaults) != 3 {
		t.Fatalf("defaults %d %v", len(defaults), err)
	}
	for _, b := range defaults {
		if b.Image == "" || !b.Active {
			t.Fatal("missing packaged seed")
		}
	}
	admin, err := e.Banners(testCtx, true)
	if err != nil || len(admin) != 3 {
		t.Fatalf("admin %v %v", admin, err)
	}
	for _, banner := range admin {
		if _, err = e.SaveBanner(testCtx, testAdmin, banner.ID, "hide-"+banner.ID, BannerInput{Title: banner.Title, Image: banner.Image, Active: false, SortOrder: banner.SortOrder, ExpectedVersion: banner.Version}); err != nil {
			t.Fatal(err)
		}
	}
	in := bannerFixture(t)
	if _, err = e.SaveBanner(testCtx, testCustomer, "", "banner-foreign-write", in); ProblemOf(err).Status != 403 {
		t.Fatal(err)
	}
	created, err := e.SaveBanner(testCtx, testAdmin, "", "banner-create-key", in)
	if err != nil {
		t.Fatal(err)
	}
	repeated, err := e.SaveBanner(testCtx, testAdmin, "", "banner-create-key", in)
	if err != nil || repeated.ID != created.ID {
		t.Fatalf("%+v %v", repeated, err)
	}
	visible, _ := e.Banners(testCtx, false)
	if len(visible) != 1 || visible[0].Image != in.Image || visible[0].TargetURL != in.TargetURL {
		t.Fatal(visible)
	}
	in.ExpectedVersion = 1
	in.Title = "修改标题"
	in.Active = false
	updated, err := e.SaveBanner(testCtx, testAdmin, created.ID, "banner-update-key", in)
	if err != nil || updated.Version != 2 {
		t.Fatalf("%+v %v", updated, err)
	}
	if _, err = e.SaveBanner(testCtx, testAdmin, created.ID, "banner-stale-key", in); ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
	fallback, _ := e.Banners(testCtx, false)
	if len(fallback) != 0 {
		t.Fatal("explicitly disabled banners must remain hidden")
	}
	unconfigured := NewMemoryStore()
	if err := unconfigured.Update(testCtx, func(s *State) error { s.Banners = map[string]*Banner{}; return nil }); err != nil {
		t.Fatal(err)
	}
	defensive, err := NewEngine(unconfigured).Banners(testCtx, false)
	if err != nil || len(defensive) != 3 {
		t.Fatal("an unconfigured state must retain the defensive packaged fallback", err)
	}
	r, _, _, banner, err := e.ShopOperation(testCtx, testAdmin, "banner-update-key")
	if err != nil || r.ResourceType != "banner" || banner.ID != created.ID {
		t.Fatalf("%+v %v", banner, err)
	}
	if _, _, _, _, err = e.ShopOperation(testCtx, testCustomer, "banner-update-key"); ProblemOf(err).Status != 404 {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	disk := NewEngine(file)
	saved, err := disk.SaveBanner(testCtx, testAdmin, "", "banner-disk-create", bannerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	file.Close()
	file, err = OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	restored, err := NewEngine(file).Banners(testCtx, true)
	if err != nil || len(restored) != 4 {
		t.Fatalf("%+v %v", restored, err)
	}
	found := false
	for _, banner := range restored {
		if banner.ID == saved.ID && banner.Image == saved.Image {
			found = true
		}
	}
	if !found {
		t.Fatal("configured banner missing after restart")
	}
}

func TestBannerSeedsPersistOnStartupWithoutReplacingConfiguration(t *testing.T) {
	for _, empty := range []bool{true, false} {
		t.Run(map[bool]string{true: "empty map", false: "configured inactive map"}[empty], func(t *testing.T) {
			dir := t.TempDir()
			state := initialState()
			if empty {
				state.Banners = map[string]*Banner{}
			} else {
				for _, banner := range state.Banners {
					banner.Active = false
					banner.TargetURL = "https://example.org/retained"
					banner.Version = 7
				}
			}
			before, err := json.Marshal(state)
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "state.json")
			if err = os.WriteFile(path, before, 0600); err != nil {
				t.Fatal(err)
			}
			store, err := OpenFileStore(dir)
			if err != nil {
				t.Fatal(err)
			}
			store.Close()
			after, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !empty && !bytes.Equal(before, after) {
				t.Fatal("startup rewrote an existing inactive configuration")
			}
			var persisted State
			if err = json.Unmarshal(after, &persisted); err != nil || len(persisted.Banners) != 3 {
				t.Fatal("banner seeds not persisted", err)
			}
			for id, banner := range persisted.Banners {
				if empty && (banner.Version != 1 || !banner.Active || banner.TargetURL != "" || !strings.HasPrefix(id, "seed-")) {
					t.Fatal("seed identity or fields changed")
				}
			}
		})
	}
	dir := t.TempDir()
	store, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	store.Close()
	if _, err = os.Stat(filepath.Join(dir, "state.json")); err != nil {
		t.Fatal("fresh database did not persist default banners", err)
	}
}
func TestBannerUnsafeImagesAndLinksAreRejected(t *testing.T) {
	e := NewEngine(NewMemoryStore())
	for _, url := range []string{"javascript:alert(1)", "data:text/html,test", "//example.org", "https://name:password@example.org/", "https://example.org/\nheader", "file:///tmp/document"} {
		in := bannerFixture(t)
		in.TargetURL = url
		if _, err := e.SaveBanner(testCtx, testAdmin, "", uuid(), in); ProblemOf(err).Status != 422 {
			t.Fatalf("unsafe target %q: %v", url, err)
		}
	}
	for _, image := range []string{"", "http://example.org/image.png", "//example.org/img.png", "../private.png", "data:image/svg+xml;base64,PHN2Zz4=", "data:image/png;base64," + base64.StdEncoding.EncodeToString([]byte("not an image"))} {
		in := bannerFixture(t)
		in.Image = image
		if _, err := e.SaveBanner(testCtx, testAdmin, "", uuid(), in); ProblemOf(err).Status != 422 {
			t.Fatalf("unsafe image %q: %v", image, err)
		}
	}
	in := bannerFixture(t)
	in.Image = "data:image/png;base64," + base64.StdEncoding.EncodeToString(make([]byte, bannerImageLimit+1))
	if _, err := e.SaveBanner(testCtx, testAdmin, "", uuid(), in); ProblemOf(err).Status != 422 {
		t.Fatal(err)
	}
	in = bannerFixture(t)
	in.TargetURL = "http://example.org/course"
	in.Image = "https://example.org/banner.png"
	if _, err := e.SaveBanner(testCtx, testAdmin, "", uuid(), in); err != nil {
		t.Fatal(err)
	}
}
func TestShopOrderEditableUntilMerchantAccepts(t *testing.T) {
	e, o := shopSetup(t)
	if !o.Editable || o.Accepted != "" {
		t.Fatal(o)
	}
	edit := ShopAction{Action: "edit", ExpectedVersion: o.Version, Requirements: "初稿结构", Contact: "站内联系", DeliveryRequirements: "提供课程资料"}
	o, err := e.ActShopOrder(testCtx, testCustomer, o.ID, "edit-requirement-key", edit)
	if err != nil || o.Requirements != "初稿结构" || !o.Editable {
		t.Fatalf("%+v %v", o, err)
	}
	repeated, err := e.ActShopOrder(testCtx, testCustomer, o.ID, "edit-requirement-key", edit)
	if err != nil || repeated.Version != o.Version {
		t.Fatalf("%+v %v", repeated, err)
	}
	if o.Amount != 49800 || o.Quantity != 1 || o.Product.ID != "graduation-outline" {
		t.Fatal("editing changed commerce snapshot")
	}
	for _, u := range []User{testAdmin, testOther} {
		_, err = e.ActShopOrder(testCtx, u, o.ID, uuid(), ShopAction{Action: "edit", ExpectedVersion: o.Version, Requirements: "他人修改"})
		want := 403
		if u.Role == "customer" {
			want = 404
		}
		if ProblemOf(err).Status != want {
			t.Fatal(err)
		}
	}
	o = shopAct(t, e, o, testCustomer, ShopAction{Action: "pay", Channel: "wechat"})
	if !o.Editable {
		t.Fatal("payment prematurely locked requirements")
	}
	o = shopAct(t, e, o, testCustomer, ShopAction{Action: "edit", Requirements: "付款后、接单前修改", Contact: "请站内留言", DeliveryRequirements: "保留章节格式"})
	o = shopAct(t, e, o, testAdmin, ShopAction{Action: "start"})
	accepted := o.Accepted
	if o.Editable || accepted == "" {
		t.Fatal("acceptance did not lock")
	}
	_, err = e.ActShopOrder(testCtx, testCustomer, o.ID, "edit-after-accept-key", ShopAction{Action: "edit", ExpectedVersion: o.Version, Requirements: "已接单后改"})
	if ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
	o = shopAct(t, e, o, testAdmin, ShopAction{Action: "deliver", Text: "已交付"})
	if o.Accepted != accepted || o.Editable {
		t.Fatal("delivery changed acceptance")
	}
	o = shopAct(t, e, o, testCustomer, ShopAction{Action: "accept"})
	if o.Editable {
		t.Fatal("completed fulfillment editable")
	}
}
func TestShopQuickDeliveryAndCancellationLockRequirements(t *testing.T) {
	e, o := shopSetup(t)
	o = shopAct(t, e, o, testCustomer, ShopAction{Action: "pay", Channel: "alipay"})
	o = shopAct(t, e, o, testAdmin, ShopAction{Action: "deliver", Text: "快捷交付"})
	if o.Accepted == "" || o.Editable {
		t.Fatal("quick delivery failed to accept")
	}
	e2, cancelled := shopSetup(t)
	cancelled = shopAct(t, e2, cancelled, testCustomer, ShopAction{Action: "cancel"})
	if cancelled.Editable {
		t.Fatal("cancelled editable")
	}
	_, err := e2.ActShopOrder(testCtx, testCustomer, cancelled.ID, uuid(), ShopAction{Action: "edit", ExpectedVersion: cancelled.Version})
	if ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
}
func TestShopConcurrentRequirementEditAndMerchantAcceptance(t *testing.T) {
	e, o := shopSetup(t)
	o = shopAct(t, e, o, testCustomer, ShopAction{Action: "pay", Channel: "wechat"})
	var success atomic.Int32
	var wg sync.WaitGroup
	for _, command := range []struct {
		user  User
		input ShopAction
	}{{testCustomer, ShopAction{Action: "edit", ExpectedVersion: o.Version, Requirements: "并发资料"}}, {testAdmin, ShopAction{Action: "start", ExpectedVersion: o.Version}}} {
		wg.Add(1)
		go func(user User, input ShopAction) {
			defer wg.Done()
			_, err := e.ActShopOrder(testCtx, user, o.ID, uuid(), input)
			if err == nil {
				success.Add(1)
			} else if ProblemOf(err).Status != 409 {
				t.Error(err)
			}
		}(command.user, command.input)
	}
	wg.Wait()
	if success.Load() != 1 {
		t.Fatal(success.Load())
	}
	current, _ := e.ShopOrder(testCtx, testCustomer, o.ID)
	if current.Version != o.Version+1 || current.Amount != o.Amount {
		t.Fatal(current)
	}
	if current.Accepted == "" {
		current = shopAct(t, e, current, testAdmin, ShopAction{Action: "start"})
	}
	if current.Editable {
		t.Fatal("accepted order stayed editable")
	}
}
func TestHTTPShopConfigExplicitDemoCredentialsAndFormalPrivacy(t *testing.T) {
	for _, demo := range []bool{false, true} {
		e := NewEngine(NewMemoryStore())
		server := httptest.NewServer(NewAPI(e, Config{Environment: "test", AdminPassword: "fixture-admin", CustomerPassword: "fixture-customer", PaymentMode: "real", DemoMode: demo}))
		response, err := http.Get(server.URL + "/api/v1/shop-config")
		if err != nil {
			t.Fatal(err)
		}
		var value map[string]any
		if err = json.NewDecoder(response.Body).Decode(&value); err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if value["demo_mode"] != demo || response.Header.Get("Cache-Control") != "no-store" {
			t.Fatal(value, response.Header)
		}
		if demo {
			rows := value["demo_credentials"].([]any)
			if len(rows) != 2 || value["payment_mode"] != "mock" {
				t.Fatal(value)
			}
			for _, v := range rows {
				row := v.(map[string]any)
				code, result := request(t, server, "POST", "/api/v1/auth/login", "", "", map[string]any{"account": row["account"], "password": row["password"]})
				if code != 200 || !strings.HasPrefix(result["user"].(map[string]any)["avatar_url"].(string), "data:image/png;base64,") {
					t.Fatal(code, result)
				}
			}
		} else {
			if _, ok := value["demo_credentials"]; ok {
				t.Fatal("formal credentials published")
			}
			if value["payment_mode"] != "real" {
				t.Fatal(value)
			}
		}
		server.Close()
	}
}
func TestConfigDemoFlagAndForcedMock(t *testing.T) {
	t.Setenv("APP_ENV", "test")
	t.Setenv("DEMO_MODE", "1")
	t.Setenv("PAYMENT_MODE", "real")
	c, err := LoadConfig()
	if err != nil || !c.DemoMode || c.PaymentMode != "mock" {
		t.Fatalf("%+v %v", c, err)
	}
	t.Setenv("DEMO_MODE", "0")
	c, err = LoadConfig()
	if err != nil || c.DemoMode || c.PaymentMode != "real" {
		t.Fatal(c.DemoMode, c.PaymentMode, err)
	}
	t.Setenv("DEMO_MODE", "yes")
	if _, err = LoadConfig(); err == nil {
		t.Fatal("implicit demo flag accepted")
	}
}
func TestHTTPBannerUploadAndOrderEditContract(t *testing.T) {
	_, server := apiSetup(t)
	customer := loginToken(t, server, "customer")
	admin := loginToken(t, server, "admin")
	code, defaults := request(t, server, "GET", "/api/v1/banners", "", "", nil)
	if code != 200 || len(defaults["banners"].([]any)) != 3 {
		t.Fatal(code, defaults)
	}
	code, adminDefaults := request(t, server, "GET", "/api/v1/admin/banners", admin, "", nil)
	if code != 200 || len(adminDefaults["banners"].([]any)) != 3 {
		t.Fatal("default banners are not editable database rows", code)
	}
	seed := adminDefaults["banners"].([]any)[0].(map[string]any)
	seedInput := BannerInput{Title: seed["title"].(string), Image: seed["image"].(string), TargetURL: "https://example.org/seed-configured", Active: true, SortOrder: 0, ExpectedVersion: 1}
	code, changedSeed := request(t, server, "PUT", "/api/v1/admin/banners/"+seed["id"].(string), admin, "http-default-banner-edit", seedInput)
	if code != 200 || changedSeed["banner"].(map[string]any)["version"] != float64(2) {
		t.Fatal("seed edit failed", code)
	}
	code, publicSeeds := request(t, server, "GET", "/api/v1/banners", "", "", nil)
	if code != 200 || publicSeeds["banners"].([]any)[0].(map[string]any)["target_url"] != seedInput.TargetURL {
		t.Fatal("seed edit not reflected publicly", code)
	}
	in := bannerFixture(t)
	code, created := request(t, server, "POST", "/api/v1/admin/banners", admin, "http-banner-create", in)
	if code != 201 {
		t.Fatal(code, created)
	}
	banner := created["banner"].(map[string]any)
	in.ExpectedVersion = 1
	in.Title = "修改轮播"
	code, updated := request(t, server, "PUT", "/api/v1/admin/banners/"+banner["id"].(string), admin, "http-banner-edit", in)
	if code != 200 || updated["banner"].(map[string]any)["version"] != float64(2) {
		t.Fatal(code, updated)
	}
	code, _ = request(t, server, "POST", "/api/v1/admin/banners", customer, "http-banner-forbidden", in)
	if code != 403 {
		t.Fatal(code)
	}
	code, result := request(t, server, "GET", "/api/v1/shop-operations/http-banner-edit", admin, "", nil)
	if code != 200 || result["banner"].(map[string]any)["id"] != banner["id"] {
		t.Fatal(code, result)
	}
	code, result = request(t, server, "POST", "/api/v1/shop-orders", customer, "http-order-requirements", ShopCreateInput{ProductID: "editing-polish", ProductVersion: 1, Requirements: "摘要润色", Contact: "站内联系", DeliveryRequirements: "双语说明"})
	if code != 201 {
		t.Fatal(code, result)
	}
	o := result["order"].(map[string]any)
	if o["editable"] != true || o["requirements"] != "摘要润色" || o["accepted_at"] != "" {
		t.Fatal(o)
	}
	code, result = request(t, server, "POST", "/api/v1/shop-orders/"+o["id"].(string)+"/actions", customer, "http-order-edit", ShopAction{Action: "edit", ExpectedVersion: 1, Requirements: "增加术语校对", Contact: "站内回复", DeliveryRequirements: "保留段落"})
	if code != 200 || result["order"].(map[string]any)["requirements"] != "增加术语校对" {
		t.Fatal(code, result)
	}
	code, _ = request(t, server, "POST", "/api/v1/shop-orders/"+o["id"].(string)+"/actions", customer, "http-order-forge-price", map[string]any{"action": "edit", "expected_version": 2, "requirements": "内容", "amount_minor": 1})
	if code != 422 {
		t.Fatal(code)
	}
	_, err := NewEngine(NewMemoryStore()).CreateShopOrder(testCtx, testCustomer, "order-long-requirements", ShopCreateInput{ProductID: "editing-polish", ProductVersion: 1, Contact: strings.Repeat("x", 201)})
	if ProblemOf(err).Status != 422 {
		t.Fatal(err)
	}
}
