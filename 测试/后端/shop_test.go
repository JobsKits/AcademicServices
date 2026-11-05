// Created by Jobs on 2026年11月4日，星期三.
package platform

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func productInput(p *Product) ProductInput {
	return ProductInput{CategoryID: p.CategoryID, Kind: p.Kind, Name: p.Name, Summary: p.Summary, Description: p.Description, Price: p.Price, Currency: p.Currency, Image: p.Image, Sections: p.Sections, Active: p.Active, InStock: p.InStock, IsDemo: p.IsDemo, ReferencePrice: p.ReferencePrice, ExpectedVersion: p.Version}
}
func shopSetup(t *testing.T) (*Engine, *ShopOrder) {
	t.Helper()
	e := NewEngine(NewMemoryStore())
	o, err := e.CreateShopOrder(testCtx, testCustomer, "shop-create-key", ShopCreateInput{"graduation-outline", 1})
	if err != nil {
		t.Fatal(err)
	}
	return e, o
}
func shopAct(t *testing.T, e *Engine, o *ShopOrder, u User, a ShopAction) *ShopOrder {
	t.Helper()
	a.ExpectedVersion = o.Version
	out, err := e.ActShopOrder(testCtx, u, o.ID, uuid(), a)
	if err != nil {
		t.Fatalf("%s: %v", a.Action, err)
	}
	return out
}
func TestShopCatalogEditingAndSnapshot(t *testing.T) {
	e, o := shopSetup(t)
	products, err := e.Products(testCtx, false, "")
	if err != nil || len(products) != 9 {
		t.Fatalf("catalog %d %v", len(products), err)
	}
	p, err := e.Product(testCtx, o.Product.ID)
	if err != nil {
		t.Fatal(err)
	}
	in := productInput(p)
	in.Price = 12345
	in.Description = "后台编辑的完整服务介绍"
	in.Image = "https://example.org/product.png"
	in.Sections = []ProductSection{{"交付", "在线课程"}}
	in.Active = false
	in.InStock = false
	if _, err = e.SaveProduct(testCtx, testCustomer, p.ID, "shop-denied-edit", in); ProblemOf(err).Status != 403 {
		t.Fatal(err)
	}
	updated, err := e.SaveProduct(testCtx, testAdmin, p.ID, "shop-edit-product", in)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Version != 2 || updated.Price != 12345 || updated.Active || updated.InStock || updated.Image != in.Image || updated.Sections[0].Body != "在线课程" {
		t.Fatal(updated)
	}
	if _, err = e.SaveProduct(testCtx, testAdmin, p.ID, "shop-stale-edit", in); ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
	replay, err := e.SaveProduct(testCtx, testAdmin, p.ID, "shop-edit-product", in)
	if err != nil || replay.Version != 2 {
		t.Fatalf("replay %+v %v", replay, err)
	}
	if _, err = e.Product(testCtx, p.ID); ProblemOf(err).Status != 404 {
		t.Fatal(err)
	}
	if _, err = e.CreateShopOrder(testCtx, testCustomer, "shop-offline-create", ShopCreateInput{p.ID, 2}); ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
	sold, err := e.ShopOrder(testCtx, testCustomer, o.ID)
	if err != nil || sold.Product.Version != 1 || sold.Amount != 49800 || sold.Product.Description == in.Description {
		t.Fatalf("snapshot %+v %v", sold, err)
	}
	// A pending order pays its accepted snapshot even after the listing is removed.
	sold = shopAct(t, e, sold, testCustomer, ShopAction{Action: "pay", Channel: "wechat"})
	if sold.Payment.Amount != 49800 {
		t.Fatal(sold)
	}
	products, _ = e.Products(testCtx, false, "")
	if len(products) != 8 {
		t.Fatal(len(products))
	}
	in = productInput(updated)
	in.Active = true
	_, err = e.SaveProduct(testCtx, testAdmin, p.ID, "shop-restock-listing", in)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.CreateShopOrder(testCtx, testCustomer, "shop-stock-create", ShopCreateInput{p.ID, 3}); ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
}
func TestShopProductValidationAndNewProduct(t *testing.T) {
	e, _ := shopSetup(t)
	p, _ := e.Product(testCtx, "editing-polish")
	in := productInput(p)
	in.ExpectedVersion = 0
	created, err := e.SaveProduct(testCtx, testAdmin, "", "shop-new-product", in)
	if err != nil || created.ID == p.ID || created.Version != 1 {
		t.Fatalf("%+v %v", created, err)
	}
	for _, change := range []func(*ProductInput){func(x *ProductInput) { x.Price = -1 }, func(x *ProductInput) { x.Currency = "USD" }, func(x *ProductInput) { x.Kind = "physical" }, func(x *ProductInput) { x.Image = "javascript:alert(1)" }, func(x *ProductInput) { x.Image = "data:image/svg+xml;base64,PHN2Zz4=" }, func(x *ProductInput) { x.CategoryID = "unknown" }, func(x *ProductInput) { x.Image = "../secret" }, func(x *ProductInput) { x.Sections = []ProductSection{{"", "body"}} }} {
		invalid := in
		change(&invalid)
		if _, err = e.SaveProduct(testCtx, testAdmin, "", uuid(), invalid); ProblemOf(err).Status != 422 {
			t.Fatalf("accepted %+v %v", invalid, err)
		}
	}
}
func TestShopFullWorkflowAndBothChannels(t *testing.T) {
	for _, channel := range []string{"alipay", "wechat"} {
		t.Run(channel, func(t *testing.T) {
			e, o := shopSetup(t)
			if o.Status != "pending_payment" || o.SellerStatus != "awaiting_payment" {
				t.Fatal(o)
			}
			o = shopAct(t, e, o, testCustomer, ShopAction{Action: "pay", Channel: channel})
			if o.Status != "pending_completion" || o.Payment.Mode != "mock" || o.Payment.Channel != channel || !strings.HasPrefix(o.Payment.Reference, "MOCK-") || o.Payment.Amount != o.Amount {
				t.Fatal(o)
			}
			o = shopAct(t, e, o, testAdmin, ShopAction{Action: "start"})
			if o.Fulfillment != "in_progress" || o.SellerStatus != "in_progress" {
				t.Fatal(o)
			}
			o = shopAct(t, e, o, testAdmin, ShopAction{Action: "deliver", Text: "课程已开通，服务材料已提供"})
			if o.Fulfillment != "delivered" || o.SellerStatus != "awaiting_confirmation" {
				t.Fatal(o)
			}
			o = shopAct(t, e, o, testCustomer, ShopAction{Action: "accept"})
			completed := o.Completed
			if o.Status != "pending_review" || completed == "" || o.SellerStatus != "awaiting_review" {
				t.Fatal(o)
			}
			e.Now = func() time.Time { return time.Now().Add(time.Hour) }
			o = shopAct(t, e, o, testCustomer, ShopAction{Action: "review", Text: "交付清晰", Rating: 5})
			if o.Status != "completed" || o.Completed != completed || o.Review.Rating != 5 || len(o.Events) != 6 {
				t.Fatal(o)
			}
		})
	}
}
func TestShopRoleIsolationAndStateGuards(t *testing.T) {
	e, o := shopSetup(t)
	foreign := User{"foreign", "其他客户", "customer"}
	if _, err := e.ShopOrder(testCtx, foreign, o.ID); ProblemOf(err).Status != 404 {
		t.Fatal(err)
	}
	orders, _ := e.ShopOrders(testCtx, foreign)
	if len(orders) != 0 {
		t.Fatal(orders)
	}
	for _, test := range []struct {
		user   User
		action ShopAction
		status int
	}{
		{testAdmin, ShopAction{Action: "pay", Channel: "alipay"}, 403}, {testCustomer, ShopAction{Action: "deliver", Text: "越权"}, 403}, {foreign, ShopAction{Action: "pay", Channel: "wechat"}, 404},
		{testCustomer, ShopAction{Action: "accept"}, 409}, {testCustomer, ShopAction{Action: "review", Text: "未买先评", Rating: 5}, 409}, {testAdmin, ShopAction{Action: "start"}, 409}, {testCustomer, ShopAction{Action: "pay", Channel: "bad"}, 422},
	} {
		test.action.ExpectedVersion = o.Version
		_, err := e.ActShopOrder(testCtx, test.user, o.ID, uuid(), test.action)
		if ProblemOf(err).Status != test.status {
			t.Fatalf("%s: %v", test.action.Action, err)
		}
	}
	e.PaymentMode = "real"
	_, err := e.ActShopOrder(testCtx, testCustomer, o.ID, "shop-real-pay-key", ShopAction{Action: "pay", ExpectedVersion: o.Version, Channel: "wechat"})
	if ProblemOf(err).Status != 503 {
		t.Fatal(err)
	}
	still, _ := e.ShopOrder(testCtx, testCustomer, o.ID)
	if still.Payment != nil || still.Status != "pending_payment" {
		t.Fatal(still)
	}
	e.PaymentMode = "mock"
	o = shopAct(t, e, o, testCustomer, ShopAction{Action: "cancel"})
	_, err = e.ActShopOrder(testCtx, testCustomer, o.ID, "shop-cancelled-pay", ShopAction{Action: "pay", ExpectedVersion: o.Version, Channel: "wechat"})
	if ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
}
func TestShopStableKeysAndConcurrentPayments(t *testing.T) {
	e, o := shopSetup(t)
	replay, err := e.CreateShopOrder(testCtx, testCustomer, "shop-create-key", ShopCreateInput{"graduation-outline", 1})
	if err != nil || replay.ID != o.ID {
		t.Fatalf("%+v %v", replay, err)
	}
	if _, err = e.CreateShopOrder(testCtx, testCustomer, "shop-create-key", ShopCreateInput{"editing-polish", 1}); ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
	var succeeded atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := e.ActShopOrder(testCtx, testCustomer, o.ID, uuid(), ShopAction{Action: "pay", ExpectedVersion: 1, Channel: "alipay"})
			if err == nil {
				succeeded.Add(1)
			} else if ProblemOf(err).Status != 409 {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if succeeded.Load() != 1 {
		t.Fatal(succeeded.Load())
	}
	orders, _ := e.ShopOrders(testCtx, testCustomer)
	if len(orders) != 1 || len(orders[0].Events) != 2 {
		t.Fatal(orders)
	}
	e2, o2 := shopSetup(t)
	a := ShopAction{Action: "pay", ExpectedVersion: 1, Channel: "wechat"}
	paid, err := e2.ActShopOrder(testCtx, testCustomer, o2.ID, "shop-pay-stable-key", a)
	if err != nil {
		t.Fatal(err)
	}
	paid2, err := e2.ActShopOrder(testCtx, testCustomer, o2.ID, "shop-pay-stable-key", a)
	if err != nil || paid2.Payment.ID != paid.Payment.ID {
		t.Fatalf("%+v %v", paid2, err)
	}
	a.Channel = "alipay"
	if _, err = e2.ActShopOrder(testCtx, testCustomer, o2.ID, "shop-pay-stable-key", a); ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
	r, _, saved, err := e2.ShopOperation(testCtx, testCustomer, "shop-pay-stable-key")
	if err != nil || saved.Payment.ID != paid.Payment.ID || r.Action != "pay" {
		t.Fatalf("%+v %v", saved, err)
	}
}
func TestShopConcurrentPriceChangeAndPurchase(t *testing.T) {
	e := NewEngine(NewMemoryStore())
	p, _ := e.Product(testCtx, "editing-polish")
	in := productInput(p)
	in.Price = 100
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, err := e.SaveProduct(testCtx, testAdmin, p.ID, "shop-price-change", in)
		if err != nil {
			t.Error(err)
		}
	}()
	go func() {
		defer wg.Done()
		o, err := e.CreateShopOrder(testCtx, testCustomer, "shop-price-order", ShopCreateInput{p.ID, 1})
		if err == nil {
			if o.Amount != p.Price || o.Product.Version != 1 {
				t.Error("mixed snapshot")
			}
		} else if ProblemOf(err).Status != 409 {
			t.Error(err)
		}
	}()
	wg.Wait()
	if _, err := e.CreateShopOrder(testCtx, testCustomer, "shop-after-price", ShopCreateInput{p.ID, 1}); ProblemOf(err).Status != 409 {
		t.Fatal(err)
	}
}
func TestShopStorageRollbackAndRestart(t *testing.T) {
	e, o := shopSetup(t)
	memory := e.Store.(*MemoryStore)
	memory.FailWrites = true
	_, err := e.ActShopOrder(testCtx, testCustomer, o.ID, "shop-failed-pay", ShopAction{Action: "pay", ExpectedVersion: 1, Channel: "alipay"})
	if err == nil {
		t.Fatal("write failure accepted")
	}
	_ = memory.View(testCtx, func(s *State) error {
		if s.ShopOrders[o.ID].Payment != nil || len(s.ShopReceipts) != 1 || len(s.ShopAudit) != 1 {
			t.Error("partial payment committed")
		}
		return nil
	})
	dir := t.TempDir()
	file, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	disk := NewEngine(file)
	saved, err := disk.CreateShopOrder(testCtx, testCustomer, "shop-disk-order", ShopCreateInput{"editing-polish", 1})
	if err != nil {
		t.Fatal(err)
	}
	saved = shopAct(t, disk, saved, testCustomer, ShopAction{Action: "pay", Channel: "wechat"})
	file.Close()
	file, err = OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	restored, err := NewEngine(file).ShopOrder(testCtx, testCustomer, saved.ID)
	if err != nil || restored.Payment.ID != saved.Payment.ID || restored.Product.ID != saved.Product.ID {
		t.Fatalf("%+v %v", restored, err)
	}
}
func TestShopRejectsInvalidStateWithoutOverwriting(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")
	for _, change := range []func(*State){
		func(s *State) { s.Schema = 0 },
		func(s *State) { s.Schema = 1 },
		func(s *State) { s.Schema = 3 },
		func(s *State) { s.Products = nil },
		func(s *State) { s.ShopOrders = nil },
		func(s *State) { s.Products["broken"] = nil },
		func(s *State) { s.ShopOrders["broken"] = nil },
	} {
		decoded := initialState()
		change(decoded)
		broken, _ := json.Marshal(decoded)
		if err := os.WriteFile(path, broken, 0600); err != nil {
			t.Fatal(err)
		}
		if bad, err := OpenFileStore(dir); err == nil {
			bad.Close()
			t.Fatal("invalid state accepted")
		}
		got, _ := os.ReadFile(path)
		if string(got) != string(broken) {
			t.Fatal("invalid data overwritten")
		}
	}
}
func TestHTTPShopCatalogAdminOrderAndCORS(t *testing.T) {
	_, server := apiSetup(t)
	customer := loginToken(t, server, "customer")
	admin := loginToken(t, server, "admin")
	other := loginToken(t, server, "customer2")
	code, catalog := request(t, server, "GET", "/api/v1/products?category_id=editing", "", "", nil)
	if code != 200 || len(catalog["products"].([]any)) != 2 || catalog["payment_mode"] != "mock" {
		t.Fatal(code, catalog)
	}
	code, _ = request(t, server, "GET", "/api/v1/admin/products", customer, "", nil)
	if code != 403 {
		t.Fatal(code)
	}
	code, created := request(t, server, "POST", "/api/v1/shop-orders", customer, "http-shop-order", ShopCreateInput{"editing-translation", 1})
	if code != 201 {
		t.Fatal(code, created)
	}
	o := created["order"].(map[string]any)
	id := o["id"].(string)
	code, _ = request(t, server, "GET", "/api/v1/shop-orders/"+id, other, "", nil)
	if code != 404 {
		t.Fatal(code)
	}
	code, paid := request(t, server, "POST", "/api/v1/shop-orders/"+id+"/actions", customer, "http-shop-pay", ShopAction{Action: "pay", ExpectedVersion: 1, Channel: "alipay"})
	if code != 200 || paid["order"].(map[string]any)["status"] != "pending_completion" {
		t.Fatal(code, paid)
	}
	code, result := request(t, server, "GET", "/api/v1/shop-operations/http-shop-pay", customer, "", nil)
	if code != 200 || result["order"].(map[string]any)["id"] != id {
		t.Fatal(code, result)
	}
	code, result = request(t, server, "GET", "/api/v1/shop-orders", other, "", nil)
	if code != 200 || len(result["orders"].([]any)) != 0 {
		t.Fatal(code, result)
	}
	code, result = request(t, server, "GET", "/api/v1/shop-orders", admin, "", nil)
	if code != 200 || len(result["orders"].([]any)) != 1 {
		t.Fatal(code, result)
	}
	p := defaultProducts()["editing-polish"]
	in := productInput(p)
	in.Price = 123
	code, result = request(t, server, "PUT", "/api/v1/admin/products/"+p.ID, admin, "http-product-edit", in)
	if code != 200 || result["product"].(map[string]any)["price_minor"].(float64) != 123 {
		t.Fatal(code, result)
	}
	code, _ = request(t, server, "POST", "/api/v1/shop-orders", customer, "http-price-forge", map[string]any{"product_id": p.ID, "product_version": 2, "amount_minor": 1})
	if code != 422 {
		t.Fatal(code)
	}
	r, _ := http.NewRequest("OPTIONS", server.URL+"/api/v1/admin/products/"+p.ID, nil)
	r.Header.Set("Origin", server.URL)
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 204 || !strings.Contains(resp.Header.Get("Access-Control-Allow-Methods"), "PUT") {
		t.Fatal(resp.StatusCode, resp.Header)
	}
}
