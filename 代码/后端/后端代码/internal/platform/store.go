package platform

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store serializes a complete business command including its audit, receipt and notification.
type Store interface {
	View(context.Context, func(*State) error) error
	Update(context.Context, func(*State) error) error
	Close()
}
type FileStore struct {
	mu          sync.Mutex
	state       *State
	dir         string
	releaseLock func()
}

func OpenFileStore(dir string) (*FileStore, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	releaseLock, e := acquireFileStoreLock(dir)
	if e != nil {
		return nil, e
	}
	store := &FileStore{state: initialState(), dir: dir, releaseLock: releaseLock}
	p := filepath.Join(dir, "state.json")
	if fi, e := os.Lstat(p); e == nil && fi.Mode()&os.ModeSymlink != 0 {
		store.Close()
		return nil, errors.New("refuse symlink state.json")
	}
	b, e := os.ReadFile(p)
	if e == nil {
		var loaded State
		if e = json.Unmarshal(b, &loaded); e != nil {
			store.Close()
			return nil, fmt.Errorf("invalid state; original file retained: %w", e)
		}
		if e = validState(&loaded); e != nil {
			store.Close()
			return nil, e
		}
		store.state = &loaded
	} else if !os.IsNotExist(e) {
		store.Close()
		return nil, e
	}
	return store, nil
}
func validState(s *State) error {
	if s.Schema != 2 || s.Cases == nil || s.Receipts == nil || len(s.Services) != 3 {
		return errors.New("unsupported state schema; do not overwrite data")
	}
	if s.Products == nil || s.ShopOrders == nil || s.ShopReceipts == nil || s.ShopAudit == nil {
		return errors.New("incomplete shop state; do not overwrite data")
	}
	for id, p := range s.Products {
		if p == nil || id != p.ID || p.Version < 1 || !moneyOK(p.Price) || p.Currency != "CNY" {
			return errors.New("invalid shop product; do not overwrite data")
		}
	}
	for id, o := range s.ShopOrders {
		if o == nil || id != o.ID || o.OwnerID == "" || o.Version < 1 || !moneyOK(o.Amount) || o.Currency != "CNY" || o.Quantity != 1 {
			return errors.New("invalid shop order; do not overwrite data")
		}
	}
	return nil
}
func (f *FileStore) View(ctx context.Context, read func(*State) error) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if e := ctx.Err(); e != nil {
		return e
	}
	return read(f.state)
}
func (f *FileStore) Update(ctx context.Context, change func(*State) error) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if e := ctx.Err(); e != nil {
		return e
	}
	next, e := cloneState(f.state)
	if e != nil {
		return e
	}
	if e = change(next); e != nil {
		return e
	}
	b, e := json.Marshal(next)
	if e != nil {
		return e
	}
	temp, e := os.CreateTemp(f.dir, ".state-*.tmp")
	if e != nil {
		return e
	}
	name := temp.Name()
	defer os.Remove(name)
	if e = temp.Chmod(0600); e != nil {
		temp.Close()
		return e
	}
	if _, e = temp.Write(b); e != nil {
		temp.Close()
		return e
	}
	if e = temp.Sync(); e != nil {
		temp.Close()
		return e
	}
	if e = temp.Close(); e != nil {
		return e
	}
	if e = os.Rename(name, filepath.Join(f.dir, "state.json")); e != nil {
		return e
	}
	f.state = next
	return nil
}
func (f *FileStore) Close() {
	if f.releaseLock != nil {
		f.releaseLock()
	}
}

type MemoryStore struct {
	mu         sync.Mutex
	state      *State
	FailWrites bool
}

func NewMemoryStore() *MemoryStore { return &MemoryStore{state: initialState()} }
func (m *MemoryStore) View(ctx context.Context, f func(*State) error) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return f(m.state)
}
func (m *MemoryStore) Update(ctx context.Context, f func(*State) error) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	n, e := cloneState(m.state)
	if e != nil {
		return e
	}
	if e = f(n); e != nil {
		return e
	}
	if m.FailWrites {
		return errors.New("injected storage failure")
	}
	m.state = n
	return nil
}
func (m *MemoryStore) Close() {}

// PGStore keeps an MVP aggregate in a locked JSONB row; the separate 29-table design is not yet a projection.
type PGStore struct{ pool *pgxpool.Pool }

const AggregateDDL = `CREATE TABLE IF NOT EXISTS academic_runtime_state (id SMALLINT PRIMARY KEY CHECK(id=1), schema_version INTEGER NOT NULL, payload JSONB NOT NULL CHECK(jsonb_typeof(payload)='object'), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());`

func OpenPGStore(ctx context.Context, url string) (*PGStore, error) {
	pool, e := pgxpool.New(ctx, url)
	if e != nil {
		return nil, e
	}
	s := &PGStore{pool}
	if e = pool.Ping(ctx); e != nil {
		pool.Close()
		return nil, e
	}
	if _, e = pool.Exec(ctx, AggregateDDL); e != nil {
		pool.Close()
		return nil, e
	}
	b, _ := json.Marshal(initialState())
	if _, e = pool.Exec(ctx, `INSERT INTO academic_runtime_state(id,schema_version,payload) VALUES(1,2,$1) ON CONFLICT(id) DO NOTHING`, string(b)); e != nil {
		pool.Close()
		return nil, e
	}
	return s, nil
}
func (p *PGStore) View(ctx context.Context, f func(*State) error) error {
	var b []byte
	if e := p.pool.QueryRow(ctx, `SELECT payload FROM academic_runtime_state WHERE id=1`).Scan(&b); e != nil {
		return e
	}
	var s State
	if e := json.Unmarshal(b, &s); e != nil {
		return e
	}
	if e := validState(&s); e != nil {
		return e
	}
	return f(&s)
}
func (p *PGStore) Update(ctx context.Context, f func(*State) error) error {
	tx, e := p.pool.Begin(ctx)
	if e != nil {
		return e
	}
	defer tx.Rollback(ctx)
	var b []byte
	if e = tx.QueryRow(ctx, `SELECT payload FROM academic_runtime_state WHERE id=1 FOR UPDATE`).Scan(&b); e != nil {
		return e
	}
	var s State
	if e = json.Unmarshal(b, &s); e != nil {
		return e
	}
	if e = validState(&s); e != nil {
		return e
	}
	if e = f(&s); e != nil {
		return e
	}
	b, e = json.Marshal(&s)
	if e != nil {
		return e
	}
	if _, e = tx.Exec(ctx, `UPDATE academic_runtime_state SET payload=$1,schema_version=2,updated_at=now() WHERE id=1`, string(b)); e != nil {
		return e
	}
	return tx.Commit(ctx)
}
func (p *PGStore) Close() { p.pool.Close() }
