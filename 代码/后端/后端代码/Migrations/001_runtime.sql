-- MVP executable persistence. Independent of the reference 29-table relational model.
CREATE TABLE IF NOT EXISTS academic_runtime_state (
    id SMALLINT PRIMARY KEY CHECK (id = 1),
    schema_version INTEGER NOT NULL,
    payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
