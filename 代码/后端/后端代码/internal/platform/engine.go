package platform

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"time"
)

type Problem struct {
	Status  int
	Code    string
	Message string
}

func (p *Problem) Error() string    { return p.Message }
func invalid(message string) error  { return &Problem{422, "validation", message} }
func conflict(message string) error { return &Problem{409, "state_conflict", message} }
func denied() error                 { return &Problem{403, "forbidden", "无权执行此操作"} }
func missing() error                { return &Problem{404, "not_found", "记录不存在或无权访问"} }

type Engine struct {
	Store       Store
	Now         func() time.Time
	PaymentMode string
}

func NewEngine(store Store) *Engine { return &Engine{Store: store, Now: time.Now, PaymentMode: "mock"} }
func (e *Engine) Services(ctx context.Context) ([]Service, error) {
	var out []Service
	err := e.Store.View(ctx, func(s *State) error { out = slices.Clone(s.Services); return nil })
	return out, err
}
func canSee(u User, c *Case) bool { return u.Role == "admin" || u.ID == c.OwnerID }
func hash(v any) string {
	b, _ := json.Marshal(v)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
func checkKey(k string) error {
	if len(k) < 8 || len(k) > 120 || strings.ContainsAny(k, "\r\n\x00") {
		return invalid("Idempotency-Key须为8至120个字符")
	}
	return nil
}
func findService(s *State, id string) *Service {
	for i := range s.Services {
		if s.Services[i].ID == id {
			return &s.Services[i]
		}
	}
	return nil
}
func receiptName(u User, k string) string { return u.ID + ":" + k }
func repeat(s *State, u User, k, h string) (*Case, bool, error) {
	if r, ok := s.Receipts[receiptName(u, k)]; ok {
		if r.Hash != h {
			return nil, true, conflict("同一提交标识不能用于不同内容")
		}
		c := s.Cases[r.CaseID]
		if c == nil || !canSee(u, c) {
			return nil, true, missing()
		}
		return publicCase(c), true, nil
	}
	return nil, false, nil
}
func (e *Engine) Cases(ctx context.Context, u User) ([]*Case, error) {
	out := []*Case{}
	err := e.Store.View(ctx, func(s *State) error {
		for _, c := range s.Cases {
			if canSee(u, c) {
				out = append(out, publicCase(c))
			}
		}
		slices.SortFunc(out, func(a, b *Case) int { return strings.Compare(b.Created, a.Created) })
		return nil
	})
	return out, err
}
func (e *Engine) Get(ctx context.Context, u User, id string) (*Case, error) {
	var out *Case
	err := e.Store.View(ctx, func(s *State) error {
		c := s.Cases[id]
		if c == nil || !canSee(u, c) {
			return missing()
		}
		out = publicCase(c)
		return nil
	})
	return out, err
}
func (e *Engine) Operation(ctx context.Context, u User, key string) (*Case, Receipt, error) {
	var out *Case
	var r Receipt
	err := e.Store.View(ctx, func(s *State) error {
		var ok bool
		r, ok = s.Receipts[receiptName(u, key)]
		if !ok {
			return missing()
		}
		c := s.Cases[r.CaseID]
		if c == nil || !canSee(u, c) {
			return missing()
		}
		out = publicCase(c)
		return nil
	})
	return out, r, err
}

type CreateInput struct {
	ServiceID   string `json:"service_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Discipline  string `json:"discipline"`
	Level       string `json:"level"`
	WordCount   int    `json:"word_count"`
	Language    string `json:"language"`
	Deadline    string `json:"deadline"`
	Contact     string `json:"contact"`
	Consent     bool   `json:"consent"`
}

func (e *Engine) Create(ctx context.Context, u User, key string, in CreateInput) (*Case, error) {
	if u.Role != "customer" {
		return nil, denied()
	}
	if err := checkKey(key); err != nil {
		return nil, err
	}
	h := hash(struct {
		Path  string
		Input CreateInput
	}{"cases", in})
	var out *Case
	err := e.Store.Update(ctx, func(s *State) error {
		if c, ok, err := repeat(s, u, key, h); ok {
			out = c
			return err
		}
		svc := findService(s, in.ServiceID)
		if svc == nil || !svc.Active {
			return conflict("当前服务未上架")
		}
		if !in.Consent {
			return invalid("请先确认服务说明及隐私授权")
		}
		if strings.TrimSpace(in.Title) == "" || len([]rune(in.Title)) > 120 || strings.TrimSpace(in.Description) == "" || len([]rune(in.Description)) > 10000 {
			return invalid("请填写120字以内标题和10000字以内需求说明")
		}
		if in.WordCount < 0 || in.WordCount > 1000000 {
			return invalid("字数须为0至1000000的整数")
		}
		if in.ServiceID == "graduation" && (strings.TrimSpace(in.Level) == "" || strings.TrimSpace(in.Discipline) == "") {
			return invalid("毕业论文请填写学历和专业")
		}
		if in.ServiceID == "journal" && strings.TrimSpace(in.Discipline) == "" {
			return invalid("普刊请填写学科方向")
		}
		if in.ServiceID == "editing" && strings.TrimSpace(in.Language) == "" {
			return invalid("编译请填写目标语种")
		}
		if in.Deadline != "" {
			if _, err := time.Parse("2006-01-02", in.Deadline); err != nil {
				return invalid("期望日期格式应为YYYY-MM-DD")
			}
		}
		now := e.Now()
		c := &Case{ID: uuid(), OwnerID: u.ID, ServiceID: in.ServiceID, Title: strings.TrimSpace(in.Title), Description: strings.TrimSpace(in.Description), Discipline: in.Discipline, Level: in.Level, WordCount: in.WordCount, Language: in.Language, Deadline: in.Deadline, Contact: in.Contact, Consent: true, Status: "pending_review", Version: 1, MaterialVersion: 1, Created: timestamp(now), Updated: timestamp(now), QuoteHistory: []Quote{}, Attachments: []Attachment{}, Messages: []Message{}, Events: []Event{}, AfterSales: []AfterSale{}}
		s.Cases[c.ID] = c
		emit(s, c, u, "created", "提交需求并确认授权", "", now)
		s.Receipts[receiptName(u, key)] = Receipt{h, c.ID, "created", u.ID, timestamp(now)}
		out = publicCase(c)
		return nil
	})
	return out, err
}

type Action struct {
	Action          string   `json:"action"`
	ExpectedVersion int      `json:"expected_version"`
	Text            string   `json:"text,omitempty"`
	Amount          *int64   `json:"amount_minor,omitempty"`
	Prepay          *int64   `json:"prepay_minor,omitempty"`
	Scope           string   `json:"scope,omitempty"`
	Expires         string   `json:"expires_at,omitempty"`
	RevisionLimit   *int     `json:"revision_limit,omitempty"`
	QuoteID         string   `json:"quote_id,omitempty"`
	Reference       string   `json:"reference,omitempty"`
	HoldID          string   `json:"hold_id,omitempty"`
	AttachmentIDs   []string `json:"attachment_ids,omitempty"`
	AfterSaleID     string   `json:"after_sale_id,omitempty"`
	DeliveryID      string   `json:"delivery_id,omitempty"`
	FeedbackID      string   `json:"feedback_id,omitempty"`
	RoundID         string   `json:"round_id,omitempty"`
	CountUnits      *int     `json:"count_units,omitempty"`
	Settlement      *int64   `json:"settlement_minor,omitempty"`
	PaymentID       string   `json:"payment_id,omitempty"`
	RefundID        string   `json:"refund_id,omitempty"`
	ChangeID        string   `json:"change_id,omitempty"`
	Deadline        string   `json:"deadline,omitempty"`
	Draft           bool     `json:"draft,omitempty"`
}

var staffActions = map[string]bool{"need_material": true, "quote": true, "withdraw_quote": true, "record_payment": true, "start": true, "pause": true, "resume": true, "deliver": true, "accept_revision": true, "cancel": true, "refund": true, "approve_refund": true, "confirm_refund": true, "mark_refund_unknown": true, "fail_refund": true, "reject_refund": true, "resolve_refund_failed": true, "close_after_sale": true, "propose_change": true}
var customerActions = map[string]bool{"supplement": true, "accept_quote": true, "decline_quote": true, "revision": true, "accept_delivery": true, "confirm_cancel": true, "reject_cancel": true, "after_sale": true, "withdraw_request": true, "confirm_change": true, "reject_change": true}

func (e *Engine) Act(ctx context.Context, u User, id, key string, a Action) (*Case, error) {
	if err := checkKey(key); err != nil {
		return nil, err
	}
	if a.Action != "message" {
		if staffActions[a.Action] {
			if u.Role != "admin" {
				return nil, denied()
			}
		} else if customerActions[a.Action] {
			if u.Role != "customer" {
				return nil, denied()
			}
		} else {
			return nil, invalid("未知业务动作")
		}
	}
	h := hash(struct {
		ID    string
		Input Action
	}{id, a})
	var out *Case
	err := e.Store.Update(ctx, func(s *State) error {
		if c, ok, err := repeat(s, u, key, h); ok {
			out = c
			return err
		}
		c := s.Cases[id]
		if c == nil || !canSee(u, c) {
			return missing()
		}
		if a.ExpectedVersion != c.Version {
			return &Problem{409, "version_conflict", "资料已变化，请刷新并核对后操作"}
		}
		if len([]rune(a.Text)) > 10000 || len(a.Reference) > 200 || len(a.Scope) > 20000 {
			return invalid("内容超过允许长度")
		}
		before := c.Status
		now := e.Now()
		if err := applyAction(s, c, u, a, now); err != nil {
			return err
		}
		c.Version++
		c.Updated = timestamp(now)
		if c.Order != nil {
			c.Status = c.Order.Status
		}
		emit(s, c, u, a.Action, a.Text, before, now)
		s.Receipts[receiptName(u, key)] = Receipt{h, c.ID, a.Action, u.ID, timestamp(now)}
		out = publicCase(c)
		return nil
	})
	return out, err
}
func requiredText(a Action) error {
	if strings.TrimSpace(a.Text) == "" {
		return invalid("请填写原因或说明")
	}
	return nil
}
func liveOrder(o *Order) bool { return o != nil && o.Status != "completed" && o.Status != "cancelled" }
func invalidateQuote(c *Case) {
	if c.Quote != nil && c.Quote.Status == "offered" {
		c.Quote.Status = "superseded"
		c.QuoteHistory = append(c.QuoteHistory, *c.Quote)
	}
	if c.Order == nil && c.Status != "closed" {
		c.Status = "pending_review"
	}
}
func latest(o *Order, group string) *Delivery {
	var d *Delivery
	for i := range o.Deliveries {
		x := &o.Deliveries[i]
		if x.AfterSaleID == group && x.Status == "released" && (d == nil || x.Version > d.Version) {
			d = x
		}
	}
	return d
}
func afterSale(c *Case, id string) *AfterSale {
	for i := range c.AfterSales {
		if c.AfterSales[i].ID == id {
			return &c.AfterSales[i]
		}
	}
	return nil
}
func feedback(o *Order, id string) *Feedback {
	for i := range o.Feedback {
		if o.Feedback[i].ID == id {
			return &o.Feedback[i]
		}
	}
	return nil
}
func payment(o *Order, id string) *Payment {
	for i := range o.Payments {
		if o.Payments[i].ID == id {
			return &o.Payments[i]
		}
	}
	return nil
}
func refund(o *Order, id string) *Refund {
	for i := range o.Refunds {
		if o.Refunds[i].ID == id {
			return &o.Refunds[i]
		}
	}
	return nil
}
func moneyOK(n int64) bool { return n >= 0 && n <= 100000000000 }
func paymentRefunded(o *Order, p string, held bool) int64 {
	var n int64
	for _, r := range o.Refunds {
		if r.PaymentID == p && (r.Status == "succeeded" || held && (r.Status == "approved" || r.Status == "processing" || r.Status == "unknown")) {
			n += r.Amount
		}
	}
	return n
}
func updateMoney(o *Order) {
	o.Paid = 0
	o.Refunded = 0
	o.RefundHeld = 0
	for _, p := range o.Payments {
		if p.Status == "succeeded" {
			o.Paid += p.Amount
		}
	}
	for _, r := range o.Refunds {
		if r.Status == "succeeded" {
			o.Refunded += r.Amount
		}
		if r.Status == "approved" || r.Status == "processing" || r.Status == "unknown" {
			o.RefundHeld += r.Amount
		}
	}
}
func checkReference(s *State, ref string, kind string) error {
	if strings.TrimSpace(ref) == "" {
		return invalid("请填写已人工核实的凭据编号")
	}
	for _, c := range s.Cases {
		if c.Order == nil {
			continue
		}
		if kind == "payment" {
			for _, p := range c.Order.Payments {
				if p.Reference == ref {
					return conflict("收款凭据已登记；请查原记录")
				}
			}
		} else {
			for _, r := range c.Order.Refunds {
				if r.Reference == ref && r.Status == "succeeded" {
					return conflict("退款凭据已登记；请查原记录")
				}
			}
		}
	}
	return nil
}
func checkAttachments(c *Case, ids []string) error {
	seen := map[string]bool{}
	for _, id := range ids {
		if seen[id] {
			return invalid("交付附件不能重复")
		}
		seen[id] = true
		found := false
		for _, f := range c.Attachments {
			if f.ID == id {
				found = true
			}
		}
		if !found {
			return invalid("附件不属于本需求")
		}
	}
	return nil
}
func applyAction(s *State, c *Case, u User, a Action, now time.Time) error {
	o := c.Order
	switch a.Action {
	case "message":
		if err := requiredText(a); err != nil {
			return err
		}
		c.Messages = append(c.Messages, Message{uuid(), u.ID, u.Name, a.Text, timestamp(now)})
	case "need_material":
		if o != nil || c.Status == "closed" {
			return conflict("仅未成交需求可要求补充材料")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		invalidateQuote(c)
		c.Status = "awaiting_material"
	case "supplement":
		if o != nil || c.Status == "closed" {
			return conflict("成交后请留言或申请变更")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		c.Description += "\n补充：" + a.Text
		c.MaterialVersion++
		invalidateQuote(c)
	case "quote":
		if o != nil || c.Status == "closed" {
			return conflict("该需求不能重新报价")
		}
		svc := findService(s, c.ServiceID)
		if svc == nil || !svc.Active {
			return conflict("服务未上架")
		}
		if a.Amount == nil || !moneyOK(*a.Amount) || a.Prepay == nil || *a.Prepay < 0 || *a.Prepay > *a.Amount || a.RevisionLimit == nil || *a.RevisionLimit < 0 || *a.RevisionLimit > 100 || strings.TrimSpace(a.Scope) == "" {
			return invalid("请填写有效金额、启动款、修改额度与完整交付条款")
		}
		end, err := time.Parse(time.RFC3339, a.Expires)
		if err != nil || !end.After(now) {
			return invalid("报价截止时间应为将来的RFC3339时间")
		}
		invalidateQuote(c)
		c.Quote = &Quote{ID: uuid(), Amount: *a.Amount, Prepay: *a.Prepay, Currency: "CNY", Scope: a.Scope, Expires: timestamp(end), RevisionLimit: *a.RevisionLimit, Status: "offered", MaterialVersion: c.MaterialVersion, Created: timestamp(now), Service: *svc}
		c.Status = "awaiting_quote_accept"
	case "withdraw_quote":
		if o != nil || c.Quote == nil || c.Quote.Status != "offered" {
			return conflict("没有可撤回的报价")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		invalidateQuote(c)
	case "accept_quote":
		if o != nil || c.Status != "awaiting_quote_accept" || c.Quote == nil || c.Quote.ID != a.QuoteID || c.Quote.Status != "offered" {
			return conflict("报价已变化或已转单")
		}
		q := c.Quote
		expiry, err := time.Parse(time.RFC3339Nano, q.Expires)
		if err != nil || !now.Before(expiry) {
			return conflict("报价已过期，请联系重新报价")
		}
		svc := findService(s, c.ServiceID)
		if svc == nil || !svc.Active || q.MaterialVersion != c.MaterialVersion {
			return conflict("服务或材料版本已变化，请重新报价")
		}
		q.Status = "accepted"
		q.Accepted = timestamp(now)
		c.QuoteHistory = append(c.QuoteHistory, *q)
		c.Order = &Order{ID: uuid(), Status: "pending_start", Amount: q.Amount, OriginalAmount: q.Amount, Prepay: q.Prepay, Currency: q.Currency, RevisionLimit: q.RevisionLimit, Scope: q.Scope, Deadline: c.Deadline, Holds: []Hold{}, Deliveries: []Delivery{}, Feedback: []Feedback{}, Payments: []Payment{}, Refunds: []Refund{}, Changes: []Change{}}
	case "decline_quote":
		if o != nil || c.Quote == nil || c.Quote.Status != "offered" {
			return conflict("没有待确认报价")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		c.Quote.Status = "declined"
		c.QuoteHistory = append(c.QuoteHistory, *c.Quote)
		c.Status = "closed"
	case "withdraw_request":
		if o != nil || c.Status == "closed" {
			return conflict("仅未成交需求可撤回")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		invalidateQuote(c)
		c.Status = "closed"
	case "record_payment":
		if o == nil {
			return conflict("尚未转订单")
		}
		if a.Amount == nil || !moneyOK(*a.Amount) || *a.Amount == 0 {
			return invalid("实收金额须为正整数分")
		}
		if err := checkReference(s, a.Reference, "payment"); err != nil {
			return err
		}
		if o.Paid+*a.Amount > 100000000000 {
			return invalid("累计实收超限")
		}
		o.Payments = append(o.Payments, Payment{uuid(), *a.Amount, a.Reference, "succeeded", o.Currency, timestamp(now)})
		updateMoney(o)
	case "start":
		if o == nil || o.Status != "pending_start" || o.Paused {
			return conflict("当前不可开工；请核对阶段与暂停条件")
		}
		if o.Paid-o.Refunded-o.RefundHeld < o.Prepay {
			return conflict("已核实净收款不足约定启动款")
		}
		o.Status = "in_service"
	case "pause":
		if !liveOrder(o) {
			return conflict("仅未结束订单可暂停")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		id := a.HoldID
		if strings.TrimSpace(id) == "" {
			id = uuid()
		}
		for _, h := range o.Holds {
			if h.ID == id {
				return conflict("暂停编号已存在")
			}
		}
		o.Holds = append(o.Holds, Hold{id, a.Text, timestamp(now), ""})
		o.Paused = true
	case "resume":
		if !liveOrder(o) {
			return conflict("当前订单不可恢复")
		}
		found := false
		for i := range o.Holds {
			if o.Holds[i].ID == a.HoldID && o.Holds[i].Closed == "" {
				o.Holds[i].Closed = timestamp(now)
				found = true
			}
		}
		if !found {
			return conflict("未找到未解决暂停项")
		}
		o.Paused = false
		for _, h := range o.Holds {
			if h.Closed == "" {
				o.Paused = true
			}
		}
	case "deliver":
		if o == nil {
			return conflict("尚未转订单")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		if err := checkAttachments(c, a.AttachmentIDs); err != nil {
			return err
		}
		if len(a.AttachmentIDs) == 0 {
			return invalid("请先上传至少一份交付文件")
		}
		if a.AfterSaleID == "" {
			if !liveOrder(o) || o.Paused || o.Status != "in_service" && o.Status != "revising" && o.Status != "awaiting_acceptance" {
				return conflict("当前不可发布主服务交付")
			}
		} else {
			af := afterSale(c, a.AfterSaleID)
			if af == nil || af.Status != "open" || o.Status != "completed" && o.Status != "cancelled" {
				return conflict("售后未开启或订单尚未结束")
			}
		}
		version := 1
		for _, d := range o.Deliveries {
			if d.AfterSaleID == a.AfterSaleID && d.Version >= version {
				version = d.Version + 1
			}
		}
		status := "released"
		if a.Draft {
			status = "draft"
		}
		ids := slices.Clone(a.AttachmentIDs)
		o.Deliveries = append(o.Deliveries, Delivery{uuid(), version, a.Text, ids, a.AfterSaleID, status, timestamp(now), ""})
		if !a.Draft && a.AfterSaleID == "" {
			o.Status = "awaiting_acceptance"
		}
	case "revision":
		if o == nil {
			return conflict("尚未转订单")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		var d *Delivery
		for i := range o.Deliveries {
			if o.Deliveries[i].ID == a.DeliveryID {
				d = &o.Deliveries[i]
			}
		}
		if d == nil || d.Status != "released" || latest(o, d.AfterSaleID).ID != d.ID {
			return conflict("请针对同组最新正式交付反馈")
		}
		if d.AfterSaleID == "" {
			if o.Status != "awaiting_acceptance" && o.Status != "revising" {
				return conflict("当前主服务不可申请修改")
			}
		} else {
			af := afterSale(c, d.AfterSaleID)
			if af == nil || af.Status != "open" {
				return conflict("售后已关闭")
			}
		}
		o.Feedback = append(o.Feedback, Feedback{ID: uuid(), DeliveryID: d.ID, Text: a.Text, Status: "requested", Created: timestamp(now)})
	case "accept_revision":
		if o == nil {
			return conflict("尚未转订单")
		}
		f := feedback(o, a.FeedbackID)
		if f == nil || f.Status != "requested" {
			return conflict("修改反馈已处理或不存在")
		}
		var d *Delivery
		for i := range o.Deliveries {
			if o.Deliveries[i].ID == f.DeliveryID {
				d = &o.Deliveries[i]
			}
		}
		if d == nil || latest(o, d.AfterSaleID).ID != d.ID {
			return conflict("该交付已有更新版本，请重新核对意见")
		}
		if strings.TrimSpace(a.RoundID) == "" || a.CountUnits == nil || *a.CountUnits < 0 || *a.CountUnits > 1 {
			return invalid("请填写修改轮次编号，count_units须为0或1")
		}
		af := afterSale(c, d.AfterSaleID)
		if d.AfterSaleID == "" {
			if !liveOrder(o) || o.Paused {
				return conflict("当前不可受理主服务修改")
			}
		} else if af == nil || af.Status != "open" {
			return conflict("售后已关闭")
		}
		existing := false
		for _, old := range o.Feedback {
			if old.Status == "accepted" && old.RoundID == a.RoundID {
				var group string
				for _, od := range o.Deliveries {
					if od.ID == old.DeliveryID {
						group = od.AfterSaleID
					}
				}
				if group == d.AfterSaleID {
					if old.CountUnits != *a.CountUnits {
						return conflict("同轮计次规则不能修改")
					}
					existing = true
				}
			}
		}
		units := *a.CountUnits
		if existing {
			units = 0
		}
		if af == nil {
			if o.RevisionUsed+units > o.RevisionLimit {
				return conflict("约定修改额度已用完，请先协商范围变更")
			}
			o.RevisionUsed += units
			o.Status = "revising"
		} else {
			if af.RevisionUsed+units > af.RevisionLimit {
				return conflict("售后修改额度已用完")
			}
			af.RevisionUsed += units
		}
		f.Status = "accepted"
		f.RoundID = a.RoundID
		f.CountUnits = *a.CountUnits
	case "accept_delivery":
		if o == nil {
			return conflict("尚未转订单")
		}
		var d *Delivery
		for i := range o.Deliveries {
			if o.Deliveries[i].ID == a.DeliveryID {
				d = &o.Deliveries[i]
			}
		}
		if d == nil || d.Status != "released" || latest(o, d.AfterSaleID).ID != d.ID || d.Accepted != "" {
			return conflict("只能确认同组最新且尚未验收的正式交付")
		}
		if d.AfterSaleID == "" {
			if o.Status != "awaiting_acceptance" || o.Paused {
				return conflict("当前不可完成主服务验收")
			}
			for _, f := range o.Feedback {
				if f.DeliveryID == d.ID && f.Status == "requested" {
					return conflict("还有待评估修改意见")
				}
			}
			o.Status = "completed"
			o.Completed = timestamp(now)
			o.AcceptedDeliveryID = d.ID
		} else {
			af := afterSale(c, d.AfterSaleID)
			if af == nil || af.Status != "open" {
				return conflict("售后已结束")
			}
		}
		d.Accepted = timestamp(now)
	case "cancel":
		if !liveOrder(o) {
			return conflict("仅未结束订单可协商取消")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		if a.Settlement == nil || !moneyOK(*a.Settlement) {
			return invalid("请明确取消后的最终结算应收（分）")
		}
		o.Cancellation = &CancelProposal{*a.Settlement, a.Text, "offered", timestamp(now), ""}
	case "confirm_cancel", "reject_cancel":
		if !liveOrder(o) || o.Cancellation == nil || o.Cancellation.Status != "offered" {
			return conflict("没有待确认的取消结算")
		}
		if a.Action == "reject_cancel" {
			o.Cancellation.Status = "rejected"
			break
		}
		o.Cancellation.Status = "accepted"
		o.Cancellation.Accepted = timestamp(now)
		o.Amount = o.Cancellation.Settlement
		o.Prepay = min(o.Prepay, o.Amount)
		o.Status = "cancelled"
	case "refund":
		if o == nil {
			return conflict("尚未转订单")
		}
		p := payment(o, a.PaymentID)
		if p == nil || p.Status != "succeeded" {
			return invalid("退款必须关联原成功收款")
		}
		if a.Amount == nil || !moneyOK(*a.Amount) || *a.Amount == 0 || *a.Amount > p.Amount-paymentRefunded(o, p.ID, true) {
			return invalid("申请金额超过原收款剩余可退额度")
		}
		o.Refunds = append(o.Refunds, Refund{ID: uuid(), PaymentID: p.ID, Amount: *a.Amount, Status: "requested", Currency: p.Currency, Created: timestamp(now)})
	case "approve_refund":
		if o == nil {
			return conflict("尚未转订单")
		}
		r := refund(o, a.RefundID)
		if r == nil || r.Status != "requested" {
			return conflict("退款申请不在待审核状态")
		}
		p := payment(o, r.PaymentID)
		if p == nil || r.Amount > p.Amount-paymentRefunded(o, p.ID, true) {
			return conflict("该原收款剩余可退额度不足")
		}
		r.Status = "approved"
		updateMoney(o)
	case "confirm_refund":
		if o == nil {
			return conflict("尚未转订单")
		}
		r := refund(o, a.RefundID)
		if r == nil || r.Status != "approved" && r.Status != "processing" && r.Status != "unknown" {
			return conflict("仅已批准或待核对退款可确认成功")
		}
		if err := checkReference(s, a.Reference, "refund"); err != nil {
			return err
		}
		r.Reference = a.Reference
		r.Status = "succeeded"
		updateMoney(o)
	case "mark_refund_unknown":
		if o == nil {
			return conflict("尚未转订单")
		}
		r := refund(o, a.RefundID)
		if r == nil || r.Status != "approved" && r.Status != "processing" {
			return conflict("仅执行中的退款可标记待核对")
		}
		r.Status = "unknown"
		updateMoney(o)
	case "resolve_refund_failed":
		if o == nil {
			return conflict("尚未转订单")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		r := refund(o, a.RefundID)
		if r == nil || r.Status != "unknown" {
			return conflict("仅待核对退款可登记原流水失败结论")
		}
		if strings.TrimSpace(a.Reference) == "" {
			return invalid("请填写原退款核对凭据编号")
		}
		r.Reference = a.Reference
		r.Status = "failed"
		updateMoney(o)
	case "fail_refund", "reject_refund":
		if o == nil {
			return conflict("尚未转订单")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		r := refund(o, a.RefundID)
		if r == nil || r.Status == "succeeded" || r.Status == "failed" || r.Status == "rejected" {
			return conflict("退款已结束或不存在")
		}
		if r.Status == "unknown" {
			return conflict("未知退款必须核对原流水，不能释放额度后换号重退")
		}
		if a.Action == "reject_refund" {
			if r.Status != "requested" {
				return conflict("仅未批准的申请可拒绝")
			}
			r.Status = "rejected"
		} else {
			r.Status = "failed"
		}
		updateMoney(o)
	case "after_sale":
		if o == nil || o.Status != "completed" && o.Status != "cancelled" {
			return conflict("订单结束后可申请售后；处理中请留言")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		c.AfterSales = append(c.AfterSales, AfterSale{ID: uuid(), Text: a.Text, Status: "open", Created: timestamp(now), RevisionLimit: o.RevisionLimit})
	case "close_after_sale":
		if o == nil {
			return conflict("尚未转订单")
		}
		if err := requiredText(a); err != nil {
			return err
		}
		af := afterSale(c, a.AfterSaleID)
		if af == nil || af.Status != "open" {
			return conflict("售后不存在或已结束")
		}
		if o.Paid-o.Refunded > o.Amount {
			return conflict("结算退款差额尚未处理，不能关闭售后")
		}
		for _, r := range o.Refunds {
			if r.Status == "requested" || r.Status == "approved" || r.Status == "processing" || r.Status == "unknown" {
				return conflict("退款义务尚未结束，不能关闭售后")
			}
		}
		af.Status = "closed"
		af.Closed = timestamp(now)
		af.Conclusion = a.Text
	case "propose_change":
		if !liveOrder(o) {
			return conflict("当前不能变更主服务条款")
		}
		if a.Amount == nil || !moneyOK(*a.Amount) || strings.TrimSpace(a.Scope) == "" {
			return invalid("请填写新应收与完整服务范围")
		}
		if a.Deadline != "" {
			if _, err := time.Parse("2006-01-02", a.Deadline); err != nil {
				return invalid("日期格式应为YYYY-MM-DD")
			}
		}
		deadline := a.Deadline
		if deadline == "" {
			deadline = o.Deadline
		}
		prepay := min(o.Prepay, *a.Amount)
		if a.Prepay != nil {
			prepay = *a.Prepay
		}
		if prepay < 0 || prepay > *a.Amount {
			return invalid("新启动款不能超过新应收")
		}
		for i := range o.Changes {
			if o.Changes[i].Status == "offered" {
				o.Changes[i].Status = "superseded"
			}
		}
		o.Changes = append(o.Changes, Change{ID: uuid(), Amount: *a.Amount, Prepay: prepay, Deadline: deadline, Scope: a.Scope, Status: "offered", Created: timestamp(now)})
	case "confirm_change", "reject_change":
		if !liveOrder(o) {
			return conflict("当前不能变更主服务条款")
		}
		var ch *Change
		for i := range o.Changes {
			if o.Changes[i].ID == a.ChangeID && o.Changes[i].Status == "offered" {
				ch = &o.Changes[i]
			}
		}
		if ch == nil {
			return conflict("变更单已变化")
		}
		if a.Action == "reject_change" {
			ch.Status = "rejected"
			break
		}
		ch.Status = "accepted"
		ch.Accepted = timestamp(now)
		o.Amount = ch.Amount
		o.Prepay = ch.Prepay
		o.Scope = ch.Scope
		o.Deadline = ch.Deadline
	default:
		return invalid("未知业务动作")
	}
	return nil
}

func (e *Engine) Upload(ctx context.Context, u User, id, key string, version int, name, mime string, data []byte) (*Case, error) {
	if err := checkKey(key); err != nil {
		return nil, err
	}
	if len(data) == 0 || len(data) > 8<<20 {
		return nil, invalid("文件须为1字节至8MB")
	}
	name = strings.TrimSpace(name)
	if name == "" || len([]rune(name)) > 200 || strings.ContainsAny(name, "/\\\x00\r\n") {
		return nil, invalid("文件名无效")
	}
	sum := sha256.Sum256(data)
	sha := hex.EncodeToString(sum[:])
	h := hash(struct {
		ID      string
		Version int
		Name    string
		Sum     string
	}{id, version, name, sha})
	var out *Case
	err := e.Store.Update(ctx, func(s *State) error {
		if c, ok, err := repeat(s, u, key, h); ok {
			out = c
			return err
		}
		c := s.Cases[id]
		if c == nil || !canSee(u, c) {
			return missing()
		}
		if c.Version != version {
			return &Problem{409, "version_conflict", "资料已变化，请刷新后上传"}
		}
		if len(c.Attachments) >= 50 {
			return invalid("每个需求最多50个文件")
		}
		var total int
		for _, f := range c.Attachments {
			total += f.Size
		}
		if total+len(data) > 64<<20 {
			return invalid("每个需求附件总量最多64MB")
		}
		before := c.Status
		now := e.Now()
		c.Attachments = append(c.Attachments, Attachment{uuid(), name, len(data), mime, sha, u.ID, timestamp(now), slices.Clone(data)})
		if c.Order == nil {
			if c.Status == "closed" {
				return conflict("需求已关闭")
			}
			c.MaterialVersion++
			invalidateQuote(c)
		}
		c.Version++
		c.Updated = timestamp(now)
		emit(s, c, u, "attachment_uploaded", name, before, now)
		s.Receipts[receiptName(u, key)] = Receipt{h, c.ID, "attachment_uploaded", u.ID, timestamp(now)}
		out = publicCase(c)
		return nil
	})
	return out, err
}
func (e *Engine) Download(ctx context.Context, u User, id, fileID string) (Attachment, error) {
	var out Attachment
	err := e.Store.View(ctx, func(s *State) error {
		c := s.Cases[id]
		if c == nil || !canSee(u, c) {
			return missing()
		}
		for _, a := range c.Attachments {
			if a.ID == fileID {
				out = a
				out.Data = slices.Clone(a.Data)
				return nil
			}
		}
		return missing()
	})
	return out, err
}
func ProblemOf(err error) *Problem {
	var p *Problem
	if errors.As(err, &p) {
		return p
	}
	return &Problem{http.StatusInternalServerError, "internal", "服务暂不可用，请保留本次提交标识并查询结果"}
}
func (e *Engine) SetService(ctx context.Context, u User, id string, active bool, version int) error {
	if u.Role != "admin" {
		return denied()
	}
	return e.Store.Update(ctx, func(s *State) error {
		svc := findService(s, id)
		if svc == nil {
			return missing()
		}
		if svc.Version != version {
			return conflict("服务版本已变化")
		}
		svc.Active = active
		svc.Version++
		if !active {
			for _, c := range s.Cases {
				if c.ServiceID == id && c.Order == nil && c.Status != "closed" {
					before := c.Status
					invalidateQuote(c)
					c.Version++
					c.Updated = timestamp(e.Now())
					emit(s, c, u, "service_offline", fmt.Sprintf("%s下架", svc.Name), before, e.Now())
				}
			}
		}
		return nil
	})
}
