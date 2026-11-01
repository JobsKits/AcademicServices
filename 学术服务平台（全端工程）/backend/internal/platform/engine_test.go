package platform

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var testCustomer = User{"customer", "客户", "customer"}
var testOther = User{"customer2", "客户2", "customer"}
var testAdmin = User{"admin", "管理", "admin"}
var testCtx = context.Background()

func int64p(v int64) *int64 { return &v }
func intp(v int) *int       { return &v }
func setup(t *testing.T) (*Engine, *Case) {
	t.Helper()
	e := NewEngine(NewMemoryStore())
	e.Now = func() time.Time { return time.Date(2026, 10, 30, 10, 0, 0, 0, time.UTC) }
	c, err := e.Create(testCtx, testCustomer, "create-001", CreateInput{ServiceID: "graduation", Title: "方法辅导", Description: "本人论文结构与方法咨询", Discipline: "计算机", Level: "本科", Consent: true})
	if err != nil {
		t.Fatal(err)
	}
	return e, c
}
func act(t *testing.T, e *Engine, c *Case, u User, a Action) *Case {
	t.Helper()
	a.ExpectedVersion = c.Version
	out, err := e.Act(testCtx, u, c.ID, uuid(), a)
	if err != nil {
		t.Fatalf("%s: %v", a.Action, err)
	}
	return out
}
func quoted(t *testing.T, e *Engine, c *Case, amount, prepay int64, rounds int) *Case {
	t.Helper()
	return act(t, e, c, testAdmin, Action{Action: "quote", Amount: int64p(amount), Prepay: int64p(prepay), Scope: "辅导与格式交付，材料齐备后5自然日，修改2轮，取消按实际确认结算", Expires: timestamp(e.Now().Add(time.Hour)), RevisionLimit: intp(rounds)})
}
func ordered(t *testing.T, e *Engine, c *Case, amount, prepay int64, rounds int) *Case {
	t.Helper()
	c = quoted(t, e, c, amount, prepay, rounds)
	return act(t, e, c, testCustomer, Action{Action: "accept_quote", QuoteID: c.Quote.ID})
}
func uploaded(t *testing.T, e *Engine, c *Case, u User) *Case {
	t.Helper()
	out, err := e.Upload(testCtx, u, c.ID, uuid(), c.Version, "论文.docx", "application/octet-stream", []byte("private document"))
	if err != nil {
		t.Fatal(err)
	}
	return out
}
func delivered(t *testing.T, e *Engine, c *Case, group string, draft bool) *Case {
	t.Helper()
	return act(t, e, c, testAdmin, Action{Action: "deliver", Text: "完成的服务材料", AttachmentIDs: []string{c.Attachments[0].ID}, AfterSaleID: group, Draft: draft})
}
func reject(t *testing.T, err error, status int) {
	t.Helper()
	if err == nil {
		t.Fatal("expected rejection")
	}
	if p := ProblemOf(err); p.Status != status {
		t.Fatalf("expected %d, got %+v", status, p)
	}
}
func TestThreeServicesValidationAndIsolation(t *testing.T) {
	e, c := setup(t)
	s, _ := e.Services(testCtx)
	if len(s) != 3 {
		t.Fatal(s)
	}
	cases, _ := e.Cases(testCtx, testOther)
	if len(cases) != 0 {
		t.Fatal("foreign customer visible")
	}
	_, err := e.Get(testCtx, testOther, c.ID)
	reject(t, err, 404)
	_, err = e.Create(testCtx, testAdmin, "admin-new", CreateInput{})
	reject(t, err, 403)
	for _, kind := range []string{"journal", "editing"} {
		in := CreateInput{ServiceID: kind, Title: "服务咨询", Description: "本人稿件", Consent: true}
		_, err = e.Create(testCtx, testCustomer, uuid(), in)
		reject(t, err, 422)
		in.Discipline = "工程"
		in.Language = "英文"
		if _, err = e.Create(testCtx, testCustomer, uuid(), in); err != nil {
			t.Fatal(err)
		}
	}
}
func TestStableCreateIdempotency(t *testing.T) {
	e, c := setup(t)
	in := CreateInput{ServiceID: "graduation", Title: "方法辅导", Description: "本人论文结构与方法咨询", Discipline: "计算机", Level: "本科", Consent: true}
	replayed, err := e.Create(testCtx, testCustomer, "create-001", in)
	if err != nil || replayed.ID != c.ID {
		t.Fatal(err)
	}
	in.Title = "改变正文"
	_, err = e.Create(testCtx, testCustomer, "create-001", in)
	reject(t, err, 409)
	cases, _ := e.Cases(testCtx, testCustomer)
	if len(cases) != 1 {
		t.Fatal("duplicate")
	}
	op, r, err := e.Operation(testCtx, testCustomer, "create-001")
	if err != nil || op.ID != c.ID || r.ActorID != testCustomer.ID {
		t.Fatal(err)
	}
	_, _, err = e.Operation(testCtx, testOther, "create-001")
	reject(t, err, 404)
}
func TestQuoteReplacementExpiryAndMaterialVersion(t *testing.T) {
	e, c := setup(t)
	c = quoted(t, e, c, 1000, 0, 2)
	old := c.Quote.ID
	c = quoted(t, e, c, 2000, 0, 2)
	_, err := e.Act(testCtx, testCustomer, c.ID, uuid(), Action{Action: "accept_quote", ExpectedVersion: c.Version, QuoteID: old})
	reject(t, err, 409)
	current := c.Quote.ID
	c = uploaded(t, e, c, testCustomer)
	_, err = e.Act(testCtx, testCustomer, c.ID, uuid(), Action{Action: "accept_quote", ExpectedVersion: c.Version, QuoteID: current})
	reject(t, err, 409)
	c = quoted(t, e, c, 2000, 0, 2)
	e.Now = func() time.Time { return time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC) }
	_, err = e.Act(testCtx, testCustomer, c.ID, uuid(), Action{Action: "accept_quote", ExpectedVersion: c.Version, QuoteID: c.Quote.ID})
	reject(t, err, 409)
}
func TestConcurrentAcceptanceAndRequote(t *testing.T) {
	e, c := setup(t)
	c = quoted(t, e, c, 100000, 0, 1)
	var success atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			a := Action{Action: "accept_quote", ExpectedVersion: c.Version, QuoteID: c.Quote.ID}
			u := testCustomer
			if i%2 == 1 {
				u = testAdmin
				a = Action{Action: "quote", ExpectedVersion: c.Version, Amount: int64p(120000), Prepay: int64p(0), Scope: "更新条款", Expires: timestamp(e.Now().Add(time.Hour)), RevisionLimit: intp(1)}
			}
			_, err := e.Act(testCtx, u, c.ID, fmt.Sprintf("race-key-%d", i), a)
			if err == nil {
				success.Add(1)
			} else if ProblemOf(err).Status != 409 {
				t.Errorf("unexpected %v", err)
			}
		}(i)
	}
	wg.Wait()
	if success.Load() != 1 {
		t.Fatalf("%d winners", success.Load())
	}
	_ = e.Store.View(testCtx, func(s *State) error {
		if len(s.Receipts) != 3 {
			t.Errorf("unexpected receipts %d", len(s.Receipts))
		}
		if len(s.Outbox) != 3 {
			t.Errorf("unexpected notices %d", len(s.Outbox))
		}
		return nil
	})
}
func TestAcceptedReplayBeforeVersionCheck(t *testing.T) {
	e, c := setup(t)
	c = quoted(t, e, c, 1000, 0, 2)
	a := Action{Action: "accept_quote", ExpectedVersion: c.Version, QuoteID: c.Quote.ID}
	first, err := e.Act(testCtx, testCustomer, c.ID, "accept-key", a)
	if err != nil {
		t.Fatal(err)
	}
	second, err := e.Act(testCtx, testCustomer, c.ID, "accept-key", a)
	if err != nil || first.Order.ID != second.Order.ID || first.Version != second.Version {
		t.Fatal("replayed transaction", err)
	}
	a.Text = "changed"
	_, err = e.Act(testCtx, testCustomer, c.ID, "accept-key", a)
	reject(t, err, 409)
}
func TestPaymentsPrepayHoldsAndTerminal(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 100000, 30000, 2)
	_, err := e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "start", ExpectedVersion: c.Version})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "record_payment", Amount: int64p(30000), Reference: "manual-bank-001"})
	_, err = e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "record_payment", ExpectedVersion: c.Version, Amount: int64p(30000), Reference: "manual-bank-001"})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "pause", Text: "等待补充文献", HoldID: "material"})
	c = act(t, e, c, testAdmin, Action{Action: "pause", Text: "等待确认排期", HoldID: "schedule"})
	c = act(t, e, c, testAdmin, Action{Action: "resume", HoldID: "material"})
	if !c.Order.Paused {
		t.Fatal("second hold lost")
	}
	_, err = e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "start", ExpectedVersion: c.Version})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "resume", HoldID: "schedule"})
	c = act(t, e, c, testAdmin, Action{Action: "start"})
	if c.Order.Status != "in_service" {
		t.Fatal(c.Order.Status)
	}
}
func TestCancelSettlementAndRefundWorkflow(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 100000, 0, 2)
	c = act(t, e, c, testAdmin, Action{Action: "record_payment", Amount: int64p(30000), Reference: "p1"})
	c = act(t, e, c, testAdmin, Action{Action: "start"})
	c = uploaded(t, e, c, testAdmin)
	c = delivered(t, e, c, "", false)
	c = act(t, e, c, testCustomer, Action{Action: "revision", DeliveryID: latest(c.Order, "").ID, Text: "调整格式"})
	c = act(t, e, c, testAdmin, Action{Action: "accept_revision", FeedbackID: c.Order.Feedback[0].ID, RoundID: "r1", CountUnits: intp(1)})
	c = act(t, e, c, testAdmin, Action{Action: "cancel", Text: "协商已完成工作结算", Settlement: int64p(10000)})
	if c.Order.Status != "revising" || c.Order.Amount != 100000 {
		t.Fatal("proposal changed effective state")
	}
	c = act(t, e, c, testCustomer, Action{Action: "confirm_cancel"})
	if c.Order.Amount != 10000 || c.Order.OriginalAmount != 100000 || c.Order.Status != "cancelled" {
		t.Fatal("bad settlement")
	}
	c = act(t, e, c, testAdmin, Action{Action: "refund", Amount: int64p(20000), PaymentID: c.Order.Payments[0].ID})
	if c.Order.Refunded != 0 || c.Order.RefundHeld != 0 {
		t.Fatal("request treated as money")
	}
	c = act(t, e, c, testAdmin, Action{Action: "approve_refund", RefundID: c.Order.Refunds[0].ID})
	if c.Order.RefundHeld != 20000 {
		t.Fatal("approval did not hold")
	}
	c = act(t, e, c, testAdmin, Action{Action: "mark_refund_unknown", RefundID: c.Order.Refunds[0].ID})
	_, err := e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "fail_refund", ExpectedVersion: c.Version, RefundID: c.Order.Refunds[0].ID, Text: "超时"})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "confirm_refund", RefundID: c.Order.Refunds[0].ID, Reference: "refund-confirmed-1"})
	if c.Order.Paid-c.Order.Refunded != c.Order.Amount || c.Order.RefundHeld != 0 {
		t.Fatal("net settlement mismatch")
	}
	c = act(t, e, c, testAdmin, Action{Action: "record_payment", Amount: int64p(1000), Reference: "late-p2"})
	if c.Order.Status != "cancelled" {
		t.Fatal("late receipt revived order")
	}
}
func TestRefundApprovalsGuardAggregateAndStart(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 100000, 30000, 2)
	c = act(t, e, c, testAdmin, Action{Action: "record_payment", Amount: int64p(30000), Reference: "p-race"})
	pid := c.Order.Payments[0].ID
	for i := 0; i < 2; i++ {
		c = act(t, e, c, testAdmin, Action{Action: "refund", Amount: int64p(20000), PaymentID: pid})
	}
	c = act(t, e, c, testAdmin, Action{Action: "approve_refund", RefundID: c.Order.Refunds[0].ID})
	_, err := e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "approve_refund", ExpectedVersion: c.Version, RefundID: c.Order.Refunds[1].ID})
	reject(t, err, 409)
	_, err = e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "start", ExpectedVersion: c.Version})
	reject(t, err, 409)
	if c.Order.RefundHeld != 20000 {
		t.Fatal("lost hold")
	}
}
func TestRevisionRoundsQuotaAndFreeUnit(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 1000, 0, 1)
	c = act(t, e, c, testAdmin, Action{Action: "start"})
	c = uploaded(t, e, c, testAdmin)
	c = delivered(t, e, c, "", false)
	d := latest(c.Order, "").ID
	for i := 0; i < 3; i++ {
		c = act(t, e, c, testCustomer, Action{Action: "revision", DeliveryID: d, Text: fmt.Sprintf("意见%d", i)})
	}
	c = act(t, e, c, testAdmin, Action{Action: "accept_revision", FeedbackID: c.Order.Feedback[0].ID, RoundID: "round-a", CountUnits: intp(1)})
	c = act(t, e, c, testAdmin, Action{Action: "accept_revision", FeedbackID: c.Order.Feedback[1].ID, RoundID: "round-a", CountUnits: intp(1)})
	if c.Order.RevisionUsed != 1 {
		t.Fatal("same round charged twice")
	}
	_, err := e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "accept_revision", ExpectedVersion: c.Version, FeedbackID: c.Order.Feedback[2].ID, RoundID: "round-b", CountUnits: intp(1)})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "accept_revision", FeedbackID: c.Order.Feedback[2].ID, RoundID: "round-b", CountUnits: intp(0)})
	if c.Order.RevisionUsed != 1 {
		t.Fatal("free correction consumed quota")
	}
}
func TestLatestReleasedGroupingAndAftersalePreservesCompletion(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 1000, 0, 2)
	c = act(t, e, c, testAdmin, Action{Action: "start"})
	c = uploaded(t, e, c, testAdmin)
	c = delivered(t, e, c, "", false)
	main := latest(c.Order, "").ID
	c = delivered(t, e, c, "", true)
	if latest(c.Order, "").ID != main {
		t.Fatal("draft invalidated release")
	}
	c = act(t, e, c, testCustomer, Action{Action: "accept_delivery", DeliveryID: main})
	completed := c.Order.Completed
	for i := 0; i < 2; i++ {
		c = act(t, e, c, testCustomer, Action{Action: "after_sale", Text: "售后修改"})
	}
	g1, g2 := c.AfterSales[0].ID, c.AfterSales[1].ID
	c = delivered(t, e, c, g1, false)
	d1 := latest(c.Order, g1).ID
	c = delivered(t, e, c, g2, false)
	d2 := latest(c.Order, g2).ID
	c = act(t, e, c, testCustomer, Action{Action: "accept_delivery", DeliveryID: d1})
	c = act(t, e, c, testCustomer, Action{Action: "accept_delivery", DeliveryID: d2})
	if c.Order.Status != "completed" || c.Order.Completed != completed || c.Order.AcceptedDeliveryID != main {
		t.Fatal("aftersale rewrote completion")
	}
}
func TestAttachmentOwnershipBytesAndImmutability(t *testing.T) {
	e, c := setup(t)
	c = uploaded(t, e, c, testCustomer)
	if len(c.Attachments[0].Data) != 0 {
		t.Fatal("private binary leaked in workspace")
	}
	a, err := e.Download(testCtx, testCustomer, c.ID, c.Attachments[0].ID)
	if err != nil || string(a.Data) != "private document" {
		t.Fatal(err)
	}
	a.Data[0] = 'X'
	a2, _ := e.Download(testCtx, testCustomer, c.ID, a.ID)
	if a2.Data[0] == 'X' {
		t.Fatal("returned mutable storage bytes")
	}
	_, err = e.Download(testCtx, testOther, c.ID, a.ID)
	reject(t, err, 404)
	c = ordered(t, e, c, 1000, 0, 1)
	c = act(t, e, c, testAdmin, Action{Action: "start"})
	_, err = e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "deliver", ExpectedVersion: c.Version, Text: "交付", AttachmentIDs: []string{"foreign-file-id"}})
	reject(t, err, 422)
}
func TestOfflineServicePreservesSoldSnapshot(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 1000, 0, 1)
	snapshot := c.Quote.Service
	if err := e.SetService(testCtx, testAdmin, "graduation", false, 1); err != nil {
		t.Fatal(err)
	}
	_, err := e.Create(testCtx, testCustomer, "offline-new", CreateInput{ServiceID: "graduation", Title: "新需求", Description: "内容", Discipline: "专业", Level: "本科", Consent: true})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "start"})
	if c.Quote.Service != snapshot {
		t.Fatal("sold snapshot changed")
	}
}
func TestStorageFailureRollsBackAuditOutboxReceipt(t *testing.T) {
	e, c := setup(t)
	store := e.Store.(*MemoryStore)
	store.FailWrites = true
	_, err := e.Act(testCtx, testCustomer, c.ID, "failure-key", Action{Action: "message", ExpectedVersion: c.Version, Text: "应回滚"})
	if err == nil {
		t.Fatal("missing storage failure")
	}
	_ = store.View(testCtx, func(s *State) error {
		if s.Cases[c.ID].Version != 1 || len(s.Cases[c.ID].Messages) != 0 || len(s.Audit) != 1 || len(s.Outbox) != 1 || len(s.Receipts) != 1 {
			t.Fatal("partial commit")
		}
		return nil
	})
	store.FailWrites = false
	c = act(t, e, c, testCustomer, Action{Action: "message", Text: "重试写入"})
	if c.Version != 2 {
		t.Fatal("bad retry")
	}
}
func TestFilePersistenceLockAndCorruptionProtection(t *testing.T) {
	dir := t.TempDir()
	s, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	if other, err := OpenFileStore(dir); err == nil {
		other.Close()
		t.Fatal("second process may open file store")
	}
	e := NewEngine(s)
	c, err := e.Create(testCtx, testCustomer, "persist-key", CreateInput{ServiceID: "editing", Title: "翻译", Description: "本人摘要", Language: "英文", Consent: true})
	if err != nil {
		t.Fatal(err)
	}
	s.Close()
	s, err = OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	e = NewEngine(s)
	found, _, err := e.Operation(testCtx, testCustomer, "persist-key")
	if err != nil || found.ID != c.ID {
		t.Fatal("lost persistent receipt", err)
	}
	s.Close()
	p := filepath.Join(dir, "state.json")
	_ = os.WriteFile(p, []byte("broken"), 0600)
	_, err = OpenFileStore(dir)
	if err == nil {
		t.Fatal("silently accepted corrupt file")
	}
	b, _ := os.ReadFile(p)
	if string(b) != "broken" {
		t.Fatal("overwrote corruption")
	}
}
func TestServiceStaffAndForeignActionGuards(t *testing.T) {
	e, c := setup(t)
	_, err := e.Act(testCtx, testCustomer, c.ID, uuid(), Action{Action: "quote", ExpectedVersion: c.Version})
	reject(t, err, 403)
	_, err = e.Act(testCtx, testOther, c.ID, uuid(), Action{Action: "message", ExpectedVersion: c.Version, Text: "foreign"})
	reject(t, err, 404)
	_, err = e.Act(testCtx, testCustomer, c.ID, uuid(), Action{Action: "message", ExpectedVersion: 0, Text: "stale"})
	reject(t, err, 409)
	_, err = e.Act(testCtx, testCustomer, c.ID, "short", Action{Action: "message", ExpectedVersion: 1, Text: "text"})
	reject(t, err, 422)
}
func TestPostgresIntegration(t *testing.T) {
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("set TEST_DATABASE_URL to a dedicated empty PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(testCtx, 30*time.Second)
	defer cancel()
	s1, err := OpenPGStore(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer s1.Close()
	s2, err := OpenPGStore(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer s2.Close()
	var existing int
	_ = s1.View(ctx, func(s *State) error { existing = len(s.Cases); return nil })
	if existing != 0 {
		t.Fatal("integration database must be empty")
	}
	e1, e2 := NewEngine(s1), NewEngine(s2)
	in := CreateInput{ServiceID: "editing", Title: "PG事务测试", Description: "独立测试数据", Language: "英文", Consent: true}
	var wg sync.WaitGroup
	ids := make(chan string, 2)
	for _, e := range []*Engine{e1, e2} {
		wg.Add(1)
		go func(e *Engine) {
			defer wg.Done()
			c, err := e.Create(ctx, testCustomer, "pg-concurrent-key", in)
			if err != nil {
				t.Error(err)
				return
			}
			ids <- c.ID
		}(e)
	}
	wg.Wait()
	close(ids)
	id := ""
	for v := range ids {
		if id != "" && v != id {
			t.Fatal("cross-instance duplicate")
		}
		id = v
	}
	if err = s1.View(ctx, func(s *State) error {
		if len(s.Cases) != 1 || len(s.Outbox) != 1 || len(s.Receipts) != 1 {
			return errors.New("cross-instance partial transaction")
		}
		b, _ := json.Marshal(s)
		if len(b) == 0 {
			return errors.New("empty state")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}
func TestChangeRequiresConfirmationPreservesInitialAndDeadline(t *testing.T) {
	e, c := setup(t)
	c.Deadline = "2026-12-01"
	_ = e.Store.Update(testCtx, func(s *State) error { s.Cases[c.ID].Deadline = c.Deadline; return nil })
	c = ordered(t, e, c, 100000, 30000, 2)
	c = act(t, e, c, testAdmin, Action{Action: "propose_change", Amount: int64p(20000), Scope: "双方缩减后的交付范围"})
	if c.Order.Amount != 100000 {
		t.Fatal("proposal applied without customer acceptance")
	}
	id := c.Order.Changes[0].ID
	c = act(t, e, c, testCustomer, Action{Action: "confirm_change", ChangeID: id})
	if c.Order.Amount != 20000 || c.Order.Prepay != 20000 || c.Order.OriginalAmount != 100000 || c.Order.Deadline != "2026-12-01" {
		t.Fatal("change lost frozen terms", c.Order)
	}
}
func TestUnknownRefundResolutionAndAftersaleCloseGuard(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 100000, 0, 2)
	c = act(t, e, c, testAdmin, Action{Action: "record_payment", Amount: int64p(30000), Reference: "unknown-pay"})
	c = act(t, e, c, testAdmin, Action{Action: "cancel", Text: "双方结算", Settlement: int64p(10000)})
	c = act(t, e, c, testCustomer, Action{Action: "confirm_cancel"})
	c = act(t, e, c, testCustomer, Action{Action: "after_sale", Text: "确认退款进度"})
	af := c.AfterSales[0].ID
	c = act(t, e, c, testAdmin, Action{Action: "refund", Amount: int64p(20000), PaymentID: c.Order.Payments[0].ID})
	rid := c.Order.Refunds[0].ID
	_, err := e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "close_after_sale", ExpectedVersion: c.Version, AfterSaleID: af, Text: "处理完成"})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "approve_refund", RefundID: rid})
	c = act(t, e, c, testAdmin, Action{Action: "mark_refund_unknown", RefundID: rid})
	c = act(t, e, c, testAdmin, Action{Action: "resolve_refund_failed", RefundID: rid, Reference: "bank-original-ref-failed", Text: "核对原交易，银行确认未退款"})
	if c.Order.RefundHeld != 0 || c.Order.Refunded != 0 {
		t.Fatal("failed result did not release reservation")
	}
	_, err = e.Act(testCtx, testAdmin, c.ID, uuid(), Action{Action: "close_after_sale", ExpectedVersion: c.Version, AfterSaleID: af, Text: "仍需退款"})
	reject(t, err, 409)
	c = act(t, e, c, testAdmin, Action{Action: "refund", Amount: int64p(20000), PaymentID: c.Order.Payments[0].ID})
	rid = c.Order.Refunds[len(c.Order.Refunds)-1].ID
	c = act(t, e, c, testAdmin, Action{Action: "approve_refund", RefundID: rid})
	c = act(t, e, c, testAdmin, Action{Action: "confirm_refund", RefundID: rid, Reference: "successful-new-refund-after-failure"})
	c = act(t, e, c, testAdmin, Action{Action: "close_after_sale", AfterSaleID: af, Text: "退款已核对完成"})
	if c.AfterSales[0].Status != "closed" {
		t.Fatal("aftersale not closed")
	}
}
func TestSparseStateIsRejected(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "state.json")
	b := []byte(`{"schema":1}`)
	if err := os.WriteFile(p, b, 0600); err != nil {
		t.Fatal(err)
	}
	s, err := OpenFileStore(dir)
	if err == nil {
		s.Close()
		t.Fatal("sparse state silently replaced data")
	}
	got, _ := os.ReadFile(p)
	if string(got) != string(b) {
		t.Fatal("invalid file overwritten")
	}
}
func TestConcurrentFinalAcceptanceAndCancel(t *testing.T) {
	e, c := setup(t)
	c = ordered(t, e, c, 100000, 0, 2)
	c = act(t, e, c, testAdmin, Action{Action: "start"})
	c = uploaded(t, e, c, testAdmin)
	c = delivered(t, e, c, "", false)
	c = act(t, e, c, testAdmin, Action{Action: "cancel", Text: "待用户选择", Settlement: int64p(10000)})
	a1 := Action{Action: "confirm_cancel", ExpectedVersion: c.Version}
	a2 := Action{Action: "accept_delivery", ExpectedVersion: c.Version, DeliveryID: latest(c.Order, "").ID}
	var count atomic.Int32
	var wg sync.WaitGroup
	for _, a := range []Action{a1, a2} {
		wg.Add(1)
		go func(a Action) {
			defer wg.Done()
			_, err := e.Act(testCtx, testCustomer, c.ID, uuid(), a)
			if err == nil {
				count.Add(1)
			} else if ProblemOf(err).Status != 409 {
				t.Error(err)
			}
		}(a)
	}
	wg.Wait()
	if count.Load() != 1 {
		t.Fatal("terminal conflict had multiple winners")
	}
}
