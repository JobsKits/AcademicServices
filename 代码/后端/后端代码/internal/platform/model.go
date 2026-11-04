// Package platform implements the versioned academic service workflow.
// Created by Jobs on 2026年10月30日，星期五.
package platform

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"
)

type User struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Role string `json:"role"`
}
type Service struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Summary     string `json:"summary"`
	Description string `json:"description"`
	Active      bool   `json:"active"`
	Version     int    `json:"version"`
}

func defaultServices() []Service {
	return []Service{{"graduation", "毕业论文", "选题与写作辅导", "选题、结构、方法及格式辅导；具体交付以确认报价为准。", true, 1}, {"journal", "普刊", "期刊咨询与稿件服务", "期刊信息咨询、稿件整理与投稿流程协助；录用由期刊独立决定。", true, 1}, {"editing", "编译", "学术翻译与语言润色", "基于本人稿件提供翻译、语言与格式服务；具体语种及范围以报价为准。", true, 1}}
}

type Quote struct {
	ID              string  `json:"id"`
	Amount          int64   `json:"amount_minor"`
	Prepay          int64   `json:"prepay_minor"`
	Currency        string  `json:"currency"`
	Scope           string  `json:"scope"`
	Expires         string  `json:"expires_at"`
	RevisionLimit   int     `json:"revision_limit"`
	Status          string  `json:"status"`
	MaterialVersion int     `json:"material_version"`
	Created         string  `json:"created_at"`
	Accepted        string  `json:"accepted_at,omitempty"`
	Service         Service `json:"service_snapshot"`
}
type Hold struct {
	ID     string `json:"id"`
	Reason string `json:"reason"`
	Opened string `json:"opened_at"`
	Closed string `json:"closed_at,omitempty"`
}
type Delivery struct {
	ID            string   `json:"id"`
	Version       int      `json:"version"`
	Text          string   `json:"text"`
	AttachmentIDs []string `json:"attachment_ids"`
	AfterSaleID   string   `json:"after_sale_id,omitempty"`
	Status        string   `json:"status"`
	Created       string   `json:"created_at"`
	Accepted      string   `json:"accepted_at,omitempty"`
}
type Feedback struct {
	ID         string `json:"id"`
	DeliveryID string `json:"delivery_id"`
	Text       string `json:"text"`
	Status     string `json:"status"`
	RoundID    string `json:"round_id,omitempty"`
	CountUnits int    `json:"count_units"`
	Created    string `json:"created_at"`
}
type Payment struct {
	ID        string `json:"id"`
	Amount    int64  `json:"amount_minor"`
	Reference string `json:"reference"`
	Status    string `json:"status"`
	Currency  string `json:"currency"`
	Created   string `json:"created_at"`
}
type Refund struct {
	ID        string `json:"id"`
	PaymentID string `json:"payment_id"`
	Amount    int64  `json:"amount_minor"`
	Reference string `json:"reference"`
	Status    string `json:"status"`
	Currency  string `json:"currency"`
	Created   string `json:"created_at"`
}
type CancelProposal struct {
	Settlement int64  `json:"settlement_minor"`
	Reason     string `json:"reason"`
	Status     string `json:"status"`
	Created    string `json:"created_at"`
	Accepted   string `json:"accepted_at,omitempty"`
}
type Change struct {
	ID       string `json:"id"`
	Amount   int64  `json:"amount_minor"`
	Prepay   int64  `json:"prepay_minor"`
	Deadline string `json:"deadline"`
	Scope    string `json:"scope"`
	Status   string `json:"status"`
	Created  string `json:"created_at"`
	Accepted string `json:"accepted_at,omitempty"`
}
type Order struct {
	ID                 string          `json:"id"`
	Status             string          `json:"status"`
	Amount             int64           `json:"amount_minor"`
	OriginalAmount     int64           `json:"original_amount_minor"`
	Prepay             int64           `json:"prepay_minor"`
	Currency           string          `json:"currency"`
	Paid               int64           `json:"paid_minor"`
	Refunded           int64           `json:"refunded_minor"`
	RefundHeld         int64           `json:"refund_held_minor"`
	RevisionUsed       int             `json:"revision_used"`
	RevisionLimit      int             `json:"revision_limit"`
	Paused             bool            `json:"paused"`
	Holds              []Hold          `json:"holds"`
	Deliveries         []Delivery      `json:"deliveries"`
	Feedback           []Feedback      `json:"feedback"`
	Payments           []Payment       `json:"payments"`
	Refunds            []Refund        `json:"refunds"`
	Cancellation       *CancelProposal `json:"cancellation,omitempty"`
	Changes            []Change        `json:"changes"`
	Scope              string          `json:"scope"`
	Deadline           string          `json:"deadline"`
	Completed          string          `json:"completed_at,omitempty"`
	AcceptedDeliveryID string          `json:"accepted_delivery_id,omitempty"`
}
type Attachment struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Size     int    `json:"size"`
	MIME     string `json:"mime"`
	SHA256   string `json:"sha256"`
	Uploader string `json:"uploader_id"`
	Created  string `json:"created_at"`
	Data     []byte `json:"data,omitempty"`
}
type Message struct {
	ID         string `json:"id"`
	AuthorID   string `json:"author_id"`
	AuthorName string `json:"author_name"`
	Text       string `json:"text"`
	Created    string `json:"created_at"`
}
type Event struct {
	ID      string `json:"id"`
	CaseID  string `json:"case_id"`
	ActorID string `json:"actor_id"`
	Action  string `json:"action"`
	Text    string `json:"text"`
	Before  string `json:"before"`
	After   string `json:"after"`
	Version int    `json:"version"`
	Created string `json:"created_at"`
}
type AfterSale struct {
	ID            string `json:"id"`
	Text          string `json:"text"`
	Status        string `json:"status"`
	Created       string `json:"created_at"`
	Closed        string `json:"closed_at,omitempty"`
	Conclusion    string `json:"conclusion,omitempty"`
	RevisionUsed  int    `json:"revision_used"`
	RevisionLimit int    `json:"revision_limit"`
}
type Case struct {
	ID              string       `json:"id"`
	OwnerID         string       `json:"owner_id"`
	ServiceID       string       `json:"service_id"`
	Title           string       `json:"title"`
	Description     string       `json:"description"`
	Discipline      string       `json:"discipline"`
	Level           string       `json:"level"`
	WordCount       int          `json:"word_count"`
	Language        string       `json:"language"`
	Deadline        string       `json:"deadline"`
	Contact         string       `json:"contact"`
	Consent         bool         `json:"consent"`
	Status          string       `json:"status"`
	Version         int          `json:"version"`
	MaterialVersion int          `json:"material_version"`
	Created         string       `json:"created_at"`
	Updated         string       `json:"updated_at"`
	Quote           *Quote       `json:"quote"`
	QuoteHistory    []Quote      `json:"quote_history"`
	Order           *Order       `json:"order"`
	Attachments     []Attachment `json:"attachments"`
	Messages        []Message    `json:"messages"`
	Events          []Event      `json:"events"`
	AfterSales      []AfterSale  `json:"after_sales"`
}
type Receipt struct {
	Hash    string `json:"hash"`
	CaseID  string `json:"case_id"`
	Action  string `json:"action"`
	ActorID string `json:"actor_id"`
	Created string `json:"created_at"`
}
type Notice struct {
	ID        string `json:"id"`
	EventID   string `json:"event_id"`
	CaseID    string `json:"case_id"`
	Recipient string `json:"recipient"`
	Status    string `json:"status"`
	Attempts  int    `json:"attempts"`
	Created   string `json:"created_at"`
}
type State struct {
	Schema   int                `json:"schema"`
	Services []Service          `json:"services"`
	Cases    map[string]*Case   `json:"cases"`
	Receipts map[string]Receipt `json:"receipts"`
	Audit    []Event            `json:"audit"`
	Outbox   []Notice           `json:"outbox"`
}

func initialState() *State {
	return &State{1, defaultServices(), map[string]*Case{}, map[string]Receipt{}, []Event{}, []Notice{}}
}
func cloneState(s *State) (*State, error) {
	b, e := json.Marshal(s)
	if e != nil {
		return nil, e
	}
	var d State
	e = json.Unmarshal(b, &d)
	return &d, e
}
func publicCase(c *Case) *Case {
	b, _ := json.Marshal(c)
	var d Case
	_ = json.Unmarshal(b, &d)
	for i := range d.Attachments {
		d.Attachments[i].Data = nil
	}
	return &d
}
func uuid() string {
	var b [16]byte
	if _, e := rand.Read(b[:]); e != nil {
		panic(e)
	}
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	s := hex.EncodeToString(b[:])
	return fmt.Sprintf("%s-%s-%s-%s-%s", s[:8], s[8:12], s[12:16], s[16:20], s[20:])
}
func timestamp(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }
func emit(s *State, c *Case, u User, action, text, before string, now time.Time) {
	e := Event{uuid(), c.ID, u.ID, action, text, before, c.Status, c.Version, timestamp(now)}
	c.Events = append(c.Events, e)
	s.Audit = append(s.Audit, e)
	recipient := c.OwnerID
	if u.Role == "customer" {
		recipient = "admin"
	}
	s.Outbox = append(s.Outbox, Notice{uuid(), e.ID, c.ID, recipient, "pending", 0, timestamp(now)})
}
