DROP TABLE IF EXISTS history;
DROP TYPE IF EXISTS history_type;
DROP TABLE IF EXISTS instructions;
DROP TABLE IF EXISTS users;

ALTER TABLE app_settings DROP COLUMN IF EXISTS openrouter_api_key;
ALTER TABLE app_settings DROP COLUMN IF EXISTS model_name;
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS default_model_id UUID;

CREATE TABLE llm_models (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug          TEXT NOT NULL UNIQUE,
    openrouter_id TEXT NOT NULL UNIQUE,
    display_name  TEXT NOT NULL,
    is_active     BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE translation_operations (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug         TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description  TEXT,
    is_active    BOOLEAN NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE translations (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operation_id       UUID NOT NULL REFERENCES translation_operations(id),
    input_text         TEXT NOT NULL,
    model_id           UUID NOT NULL REFERENCES llm_models(id),
    candidate1         TEXT NOT NULL,
    candidate2         TEXT NOT NULL,
    candidate3         TEXT NOT NULL,
    selected_candidate SMALLINT CHECK (selected_candidate BETWEEN 1 AND 3),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reviews (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    translation_id     UUID NOT NULL REFERENCES translations(id) ON DELETE CASCADE,
    rating             SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment            TEXT,
    selected_candidate SMALLINT CHECK (selected_candidate BETWEEN 1 AND 3),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
