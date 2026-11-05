-- Academic shop runtime aggregate. Payload schema_version is currently 2.
CREATE TABLE IF NOT EXISTS academic_runtime_state (
    id SMALLINT PRIMARY KEY CHECK (id = 1),
    schema_version INTEGER NOT NULL,
    payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
