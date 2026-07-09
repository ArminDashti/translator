DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS translations;
DROP TABLE IF EXISTS translation_operations;

ALTER TABLE app_settings DROP COLUMN IF EXISTS default_model_id;

DROP TABLE IF EXISTS llm_models;
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS openrouter_api_key TEXT NOT NULL DEFAULT '';
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS model_name TEXT NOT NULL DEFAULT 'anthropic/claude-3.5-sonnet';

CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username      TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS instructions (
    key         TEXT PRIMARY KEY,
    content     TEXT NOT NULL DEFAULT '',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TYPE history_type AS ENUM (
    'simplify', 'en_fa', 'fa_en', 'term_en', 'term_fa', 'refine', 'symptoms'
);

CREATE TABLE IF NOT EXISTS history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type            history_type NOT NULL,
    input_text      TEXT NOT NULL,
    result_text     TEXT NOT NULL,
    model           TEXT NOT NULL,
    instruction_key TEXT NOT NULL,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_history_created_at ON history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_history_type ON history(type);
