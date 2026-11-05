// Created by Jobs on 2026年11月4日，星期三.
package platform

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"
)

type ProductSection struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}
type Product struct {
	ID             string           `json:"id"`
	CategoryID     string           `json:"category_id"`
	Kind           string           `json:"kind"`
	Name           string           `json:"name"`
	Summary        string           `json:"summary"`
	Description    string           `json:"description"`
	Price          int64            `json:"price_minor"`
	Currency       string           `json:"currency"`
	Image          string           `json:"image"`
	Sections       []ProductSection `json:"sections"`
	Active         bool             `json:"active"`
	InStock        bool             `json:"in_stock"`
	Version        int              `json:"version"`
	IsDemo         bool             `json:"is_demo"`
	ReferencePrice string           `json:"reference_price"`
	Created        string           `json:"created_at"`
	Updated        string           `json:"updated_at"`
}
type ProductInput struct {
	CategoryID      string           `json:"category_id"`
	Kind            string           `json:"kind"`
	Name            string           `json:"name"`
	Summary         string           `json:"summary"`
	Description     string           `json:"description"`
	Price           int64            `json:"price_minor"`
	Currency        string           `json:"currency"`
	Image           string           `json:"image"`
	Sections        []ProductSection `json:"sections"`
	Active          bool             `json:"active"`
	InStock         bool             `json:"in_stock"`
	IsDemo          bool             `json:"is_demo"`
	ReferencePrice  string           `json:"reference_price"`
	ExpectedVersion int              `json:"expected_version"`
}
type ShopPayment struct {
	ID        string `json:"id"`
	Mode      string `json:"mode"`
	Channel   string `json:"channel"`
	Status    string `json:"status"`
	Amount    int64  `json:"amount_minor"`
	Currency  string `json:"currency"`
	Reference string `json:"reference"`
	Created   string `json:"created_at"`
}
type ShopReview struct {
	Rating  int    `json:"rating"`
	Text    string `json:"text"`
	Created string `json:"created_at"`
}
type ShopEvent struct {
	ID         string `json:"id"`
	ResourceID string `json:"resource_id"`
	ActorID    string `json:"actor_id"`
	Action     string `json:"action"`
	Text       string `json:"text"`
	Before     string `json:"before"`
	After      string `json:"after"`
	Created    string `json:"created_at"`
}
type ShopOrder struct {
	ID           string       `json:"id"`
	OwnerID      string       `json:"owner_id"`
	Product      Product      `json:"product_snapshot"`
	Quantity     int          `json:"quantity"`
	Amount       int64        `json:"amount_minor"`
	Currency     string       `json:"currency"`
	Status       string       `json:"status"`
	Fulfillment  string       `json:"fulfillment_status"`
	SellerStatus string       `json:"seller_status"`
	Version      int          `json:"version"`
	Created      string       `json:"created_at"`
	Updated      string       `json:"updated_at"`
	Paid         string       `json:"paid_at,omitempty"`
	Delivered    string       `json:"delivered_at,omitempty"`
	Completed    string       `json:"completed_at,omitempty"`
	DeliveryText string       `json:"delivery_text"`
	Payment      *ShopPayment `json:"payment"`
	Review       *ShopReview  `json:"review"`
	Events       []ShopEvent  `json:"events"`
}
type ShopReceipt struct {
	Hash         string `json:"hash"`
	ResourceType string `json:"resource_type"`
	ResourceID   string `json:"resource_id"`
	Action       string `json:"action"`
	ActorID      string `json:"actor_id"`
	Created      string `json:"created_at"`
}
type ShopCreateInput struct {
	ProductID      string `json:"product_id"`
	ProductVersion int    `json:"product_version"`
}
type ShopAction struct {
	Action          string `json:"action"`
	ExpectedVersion int    `json:"expected_version"`
	Channel         string `json:"channel,omitempty"`
	Text            string `json:"text,omitempty"`
	Rating          int    `json:"rating,omitempty"`
}

func defaultProducts() map[string]*Product {
	seeds := []struct {
		id, category, kind, name, summary string
		price                             int64
		reference                         string
	}{
		{"graduation-outline", "graduation", "course", "论文提纲", "从选题到结构的论文提纲辅导", 49800, "参考站公开标价：¥498"},
		{"graduation-proposal", "graduation", "course", "开题指导报告课", "开题思路与研究方案课程", 1, "参考站公开标价：¥0.01"},
		{"graduation-mentoring", "graduation", "service", "毕业论文一对一", "针对现有写作材料的一对一辅导", 5000, "参考站公开标价：¥50"},
		{"journal-submission", "journal", "service", "审测投稿", "期刊咨询与投稿流程服务", 9900, "参考站为咨询价；本平台价格仅演示"},
		{"journal-mentoring", "journal", "service", "普刊论文一对一", "稿件结构与表达的一对一辅导", 20000, "参考站公开标价：¥200"},
		{"journal-assessment", "journal", "service", "论文专业测评", "稿件问题梳理与专业测评", 60000, "参考站公开标价：¥600"},
		{"journal-training", "journal", "course", "普刊训练营", "普刊写作与投稿知识课程", 219900, "参考站公开标价：¥2199"},
		{"editing-translation", "editing", "service", "学术翻译", "基于本人稿件的学术语言翻译", 19900, "参考站为咨询价；本平台价格仅演示"},
		{"editing-polish", "editing", "service", "学术润色", "学术语言表达与格式润色", 15900, "参考站为咨询价；本平台价格仅演示"},
	}
	out := map[string]*Product{}
	for _, s := range seeds {
		out[s.id] = &Product{ID: s.id, CategoryID: s.category, Kind: s.kind, Name: s.name, Summary: s.summary, Description: s.summary + "。此为可编辑的演示商品，服务范围、课时与交付约定由运营后台维护。", Price: s.price, Currency: "CNY", Active: true, InStock: true, Version: 1, IsDemo: true, ReferencePrice: s.reference, Created: "2026-11-04T00:00:00Z", Updated: "2026-11-04T00:00:00Z", Sections: []ProductSection{{"服务内容", s.summary}, {"购买与交付", "虚拟课程／服务，无物流。付款后由站方提供交付说明，买方确认完成后评价。"}, {"演示说明", "当前为模拟商品与模拟支付，不会扣款。商品名称及公开价格用于参考映射，演示价格不是正式经营承诺。"}}}
	}
	return out
}
func cloneProduct(p *Product) *Product {
	out := *p
	out.Sections = slices.Clone(p.Sections)
	return &out
}
func publicShopOrder(o *ShopOrder) *ShopOrder {
	b, _ := json.Marshal(o)
	var out ShopOrder
	_ = json.Unmarshal(b, &out)
	out.SellerStatus = out.Status
	switch out.Status {
	case "pending_payment":
		out.SellerStatus = "awaiting_payment"
	case "pending_completion":
		out.SellerStatus = "pending_delivery"
		if out.Fulfillment == "in_progress" {
			out.SellerStatus = "in_progress"
		}
		if out.Fulfillment == "delivered" {
			out.SellerStatus = "awaiting_confirmation"
		}
	case "pending_review":
		out.SellerStatus = "awaiting_review"
	}
	return &out
}
func validProduct(in ProductInput) error {
	if in.CategoryID != "graduation" && in.CategoryID != "journal" && in.CategoryID != "editing" {
		return invalid("商品分类无效")
	}
	if in.Kind != "course" && in.Kind != "service" {
		return invalid("商品类型须为课程或服务")
	}
	if strings.TrimSpace(in.Name) == "" || len([]rune(in.Name)) > 120 || strings.TrimSpace(in.Description) == "" || len([]rune(in.Description)) > 20000 || len([]rune(in.Summary)) > 500 {
		return invalid("请填写有效名称、简介与详情")
	}
	if !moneyOK(in.Price) || in.Currency != "CNY" {
		return invalid("价格须为有效人民币分整数")
	}
	if len(in.ReferencePrice) > 500 || len(in.Sections) > 30 {
		return invalid("商品资料过长")
	}
	for _, s := range in.Sections {
		if strings.TrimSpace(s.Title) == "" || len([]rune(s.Title)) > 120 || len([]rune(s.Body)) > 5000 {
			return invalid("详情分节标题或正文无效")
		}
	}
	if len(in.Image) > 180000 {
		return invalid("商品图片须小于约130KB")
	}
	if in.Image != "" {
		valid := false
		if strings.HasPrefix(in.Image, "data:image/png;base64,") || strings.HasPrefix(in.Image, "data:image/jpeg;base64,") || strings.HasPrefix(in.Image, "data:image/webp;base64,") {
			parts := strings.SplitN(in.Image, ",", 2)
			data, err := base64.StdEncoding.DecodeString(parts[1])
			mediaType := strings.TrimSuffix(strings.TrimPrefix(parts[0], "data:"), ";base64")
			valid = err == nil && len(data) > 0 && http.DetectContentType(data) == mediaType
		} else if parsed, err := url.Parse(in.Image); err == nil {
			valid = parsed.Scheme == "https" && parsed.Host != "" && parsed.User == nil
			if parsed.Scheme == "" && parsed.Host == "" && parsed.RawQuery == "" && parsed.Fragment == "" && !strings.ContainsAny(in.Image, "\\\r\n") && !strings.Contains(parsed.Path, "..") {
				valid = true
			}
		}
		if !valid {
			return invalid("图片须为HTTPS、打包相对地址或PNG/JPEG/WebP图片data URL")
		}
	}
	return nil
}
func (e *Engine) Products(ctx context.Context, all bool, category string) ([]*Product, error) {
	out := []*Product{}
	err := e.Store.View(ctx, func(s *State) error {
		for _, p := range s.Products {
			if (all || p.Active) && (category == "" || p.CategoryID == category) {
				out = append(out, cloneProduct(p))
			}
		}
		slices.SortFunc(out, func(a, b *Product) int { return strings.Compare(a.ID, b.ID) })
		return nil
	})
	return out, err
}
func (e *Engine) Product(ctx context.Context, id string) (*Product, error) {
	var out *Product
	err := e.Store.View(ctx, func(s *State) error {
		p := s.Products[id]
		if p == nil || !p.Active {
			return missing()
		}
		out = cloneProduct(p)
		return nil
	})
	return out, err
}
func shopRepeat(s *State, u User, key, h string) (ShopReceipt, bool, error) {
	r, ok := s.ShopReceipts[receiptName(u, key)]
	if ok && r.Hash != h {
		return r, true, conflict("同一提交标识不能用于不同内容")
	}
	return r, ok, nil
}
func shopEvent(s *State, u User, id, action, text, before, after string, now time.Time) ShopEvent {
	v := ShopEvent{ID: uuid(), ResourceID: id, ActorID: u.ID, Action: action, Text: text, Before: before, After: after, Created: timestamp(now)}
	s.ShopAudit = append(s.ShopAudit, v)
	return v
}
func (e *Engine) SaveProduct(ctx context.Context, u User, id, key string, in ProductInput) (*Product, error) {
	if u.Role != "admin" {
		return nil, denied()
	}
	if err := checkKey(key); err != nil {
		return nil, err
	}
	h := hash(struct {
		Path  string
		Input ProductInput
	}{"products/" + id, in})
	var out *Product
	err := e.Store.Update(ctx, func(s *State) error {
		if r, ok, err := shopRepeat(s, u, key, h); ok {
			if err != nil {
				return err
			}
			p := s.Products[r.ResourceID]
			if p == nil {
				return missing()
			}
			out = cloneProduct(p)
			return nil
		}
		if err := validProduct(in); err != nil {
			return err
		}
		now := e.Now()
		created := timestamp(now)
		version := 1
		productID := id
		if id != "" {
			old := s.Products[id]
			if old == nil {
				return missing()
			}
			if old.Version != in.ExpectedVersion {
				return &Problem{409, "version_conflict", "商品已变化，请刷新后核对"}
			}
			created = old.Created
			version = old.Version + 1
		} else {
			productID = uuid()
		}
		sections := slices.Clone(in.Sections)
		if sections == nil {
			sections = []ProductSection{}
		}
		p := &Product{ID: productID, CategoryID: in.CategoryID, Kind: in.Kind, Name: strings.TrimSpace(in.Name), Summary: in.Summary, Description: in.Description, Price: in.Price, Currency: in.Currency, Image: in.Image, Sections: sections, Active: in.Active, InStock: in.InStock, Version: version, IsDemo: in.IsDemo, ReferencePrice: in.ReferencePrice, Created: created, Updated: timestamp(now)}
		s.Products[productID] = p
		shopEvent(s, u, productID, "save_product", p.Name, "", "version:"+strconv.Itoa(version), now)
		s.ShopReceipts[receiptName(u, key)] = ShopReceipt{h, "product", productID, "save_product", u.ID, timestamp(now)}
		out = cloneProduct(p)
		return nil
	})
	return out, err
}
func shopCanSee(u User, o *ShopOrder) bool {
	return u.Role == "admin" || (u.Role == "customer" && u.ID == o.OwnerID)
}
func (e *Engine) ShopOrders(ctx context.Context, u User) ([]*ShopOrder, error) {
	out := []*ShopOrder{}
	err := e.Store.View(ctx, func(s *State) error {
		for _, o := range s.ShopOrders {
			if shopCanSee(u, o) {
				out = append(out, publicShopOrder(o))
			}
		}
		slices.SortFunc(out, func(a, b *ShopOrder) int { return strings.Compare(b.Created, a.Created) })
		return nil
	})
	return out, err
}
func (e *Engine) ShopOrder(ctx context.Context, u User, id string) (*ShopOrder, error) {
	var out *ShopOrder
	err := e.Store.View(ctx, func(s *State) error {
		o := s.ShopOrders[id]
		if o == nil || !shopCanSee(u, o) {
			return missing()
		}
		out = publicShopOrder(o)
		return nil
	})
	return out, err
}
func (e *Engine) CreateShopOrder(ctx context.Context, u User, key string, in ShopCreateInput) (*ShopOrder, error) {
	if u.Role != "customer" {
		return nil, denied()
	}
	if err := checkKey(key); err != nil {
		return nil, err
	}
	h := hash(struct {
		Path  string
		Input ShopCreateInput
	}{"shop-orders", in})
	var out *ShopOrder
	err := e.Store.Update(ctx, func(s *State) error {
		if r, ok, err := shopRepeat(s, u, key, h); ok {
			if err != nil {
				return err
			}
			o := s.ShopOrders[r.ResourceID]
			if o == nil || !shopCanSee(u, o) {
				return missing()
			}
			out = publicShopOrder(o)
			return nil
		}
		p := s.Products[in.ProductID]
		if p == nil || !p.Active || !p.InStock {
			return conflict("商品已下架或缺货")
		}
		if p.Version != in.ProductVersion {
			return &Problem{409, "version_conflict", "商品信息或价格已变化，请刷新后重新确认"}
		}
		now := e.Now()
		o := &ShopOrder{ID: uuid(), OwnerID: u.ID, Product: *cloneProduct(p), Quantity: 1, Amount: p.Price, Currency: p.Currency, Status: "pending_payment", Fulfillment: "pending", Version: 1, Created: timestamp(now), Updated: timestamp(now), Events: []ShopEvent{}}
		o.Events = append(o.Events, shopEvent(s, u, o.ID, "create_order", p.Name, "", o.Status, now))
		s.ShopOrders[o.ID] = o
		s.ShopReceipts[receiptName(u, key)] = ShopReceipt{h, "order", o.ID, "create_order", u.ID, timestamp(now)}
		out = publicShopOrder(o)
		return nil
	})
	return out, err
}
func (e *Engine) ActShopOrder(ctx context.Context, u User, id, key string, in ShopAction) (*ShopOrder, error) {
	if err := checkKey(key); err != nil {
		return nil, err
	}
	if in.Action == "start" || in.Action == "deliver" {
		if u.Role != "admin" {
			return nil, denied()
		}
	} else if in.Action == "pay" || in.Action == "accept" || in.Action == "review" || in.Action == "cancel" {
		if u.Role != "customer" {
			return nil, denied()
		}
	} else {
		return nil, invalid("未知商城动作")
	}
	if len([]rune(in.Text)) > 10000 {
		return nil, invalid("内容过长")
	}
	h := hash(struct {
		ID    string
		Input ShopAction
	}{id, in})
	var out *ShopOrder
	err := e.Store.Update(ctx, func(s *State) error {
		if r, ok, err := shopRepeat(s, u, key, h); ok {
			if err != nil {
				return err
			}
			o := s.ShopOrders[r.ResourceID]
			if o == nil || !shopCanSee(u, o) {
				return missing()
			}
			out = publicShopOrder(o)
			return nil
		}
		o := s.ShopOrders[id]
		if o == nil || !shopCanSee(u, o) {
			return missing()
		}
		if o.Version != in.ExpectedVersion {
			return &Problem{409, "version_conflict", "订单已变化，请刷新后核对"}
		}
		now := e.Now()
		before := o.Status + ":" + o.Fulfillment
		switch in.Action {
		case "pay":
			if o.Status != "pending_payment" || o.Payment != nil {
				return conflict("订单不处于待付款状态")
			}
			if in.Channel != "alipay" && in.Channel != "wechat" {
				return invalid("请选择支付宝或微信支付")
			}
			if e.PaymentMode != "mock" {
				return &Problem{503, "payment_unavailable", "真实支付渠道尚未配置，订单保持待付款"}
			}
			o.Payment = &ShopPayment{ID: uuid(), Mode: "mock", Channel: in.Channel, Status: "succeeded", Amount: o.Amount, Currency: o.Currency, Reference: "MOCK-" + uuid(), Created: timestamp(now)}
			o.Paid = timestamp(now)
			o.Status = "pending_completion"
		case "start":
			if o.Status != "pending_completion" || o.Fulfillment != "pending" {
				return conflict("订单当前不可开始服务")
			}
			o.Fulfillment = "in_progress"
		case "deliver":
			if o.Status != "pending_completion" || o.Fulfillment == "delivered" {
				return conflict("订单当前不可交付")
			}
			if strings.TrimSpace(in.Text) == "" {
				return invalid("请填写课程或服务交付说明")
			}
			o.Fulfillment = "delivered"
			o.DeliveryText = strings.TrimSpace(in.Text)
			o.Delivered = timestamp(now)
		case "accept":
			if o.Status != "pending_completion" || o.Fulfillment != "delivered" {
				return conflict("站方交付后才能确认完成")
			}
			o.Status = "pending_review"
			o.Completed = timestamp(now)
		case "review":
			if o.Status != "pending_review" || o.Review != nil {
				return conflict("订单当前不可评价")
			}
			if in.Rating < 1 || in.Rating > 5 || strings.TrimSpace(in.Text) == "" {
				return invalid("请填写1至5分评分及评价")
			}
			o.Review = &ShopReview{in.Rating, strings.TrimSpace(in.Text), timestamp(now)}
			o.Status = "completed"
		case "cancel":
			if o.Status != "pending_payment" || o.Payment != nil {
				return conflict("仅未付款订单可直接取消")
			}
			o.Status = "cancelled"
		}
		o.Version++
		o.Updated = timestamp(now)
		o.Events = append(o.Events, shopEvent(s, u, o.ID, in.Action, in.Text, before, o.Status+":"+o.Fulfillment, now))
		s.ShopReceipts[receiptName(u, key)] = ShopReceipt{h, "order", o.ID, in.Action, u.ID, timestamp(now)}
		out = publicShopOrder(o)
		return nil
	})
	return out, err
}
func (e *Engine) ShopOperation(ctx context.Context, u User, key string) (ShopReceipt, *Product, *ShopOrder, error) {
	var receipt ShopReceipt
	var product *Product
	var order *ShopOrder
	err := e.Store.View(ctx, func(s *State) error {
		var ok bool
		receipt, ok = s.ShopReceipts[receiptName(u, key)]
		if !ok {
			return missing()
		}
		if receipt.ResourceType == "product" {
			if u.Role != "admin" {
				return missing()
			}
			p := s.Products[receipt.ResourceID]
			if p == nil {
				return missing()
			}
			product = cloneProduct(p)
		} else {
			o := s.ShopOrders[receipt.ResourceID]
			if o == nil || !shopCanSee(u, o) {
				return missing()
			}
			order = publicShopOrder(o)
		}
		return nil
	})
	return receipt, product, order, err
}
