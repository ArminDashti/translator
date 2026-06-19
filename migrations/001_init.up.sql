CREATE TABLE llm_models (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug          TEXT NOT NULL UNIQUE,
    openrouter_id TEXT NOT NULL UNIQUE,
    display_name  TEXT NOT NULL,
    is_active     BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app_settings (
    id               INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    default_model_id UUID REFERENCES llm_models(id) ON DELETE SET NULL,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app_settings (id) VALUES (1);

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

CREATE INDEX idx_translations_operation_created ON translations(operation_id, created_at DESC);
CREATE INDEX idx_reviews_translation_id ON reviews(translation_id);

INSERT INTO translation_operations (slug, display_name, description) VALUES
    ('en_to_fa', 'English → Persian', 'Machine translation from English to Persian'),
    ('en_proofreading', 'English Proofreading', 'Linguistic correction and clarity of English source text'),
    ('fa_to_en', 'Persian → English', 'Machine translation from Persian to English'),
    ('en_lexical_retrieval', 'English Lexical Retrieval', 'Retrieve candidate English terms from a semantic description');
