---
name: db-docs
description: Creates or updates db.md database schema documentation using simple markdown tables. Use when the user asks for db.md, database table docs, schema reference, or documenting tables/columns/indexes/enums from migrations or models.
---

# Database Documentation (db-docs)

Generate `db.md` in the project root. Use **simple markdown tables only** — no diagrams, no ORM code blocks unless the user asks.

## Workflow

1. **Find the schema source** (prefer in order):
   - `migrations/*.up.sql` or equivalent migration files
   - ORM/domain models (`models.go`, Entity Framework entities, Prisma schema)
   - Live database introspection only when migrations/models are missing
2. **Use the latest schema** — if migrations replace tables, document the current state, not dropped legacy tables.
3. **Write or update** `db.md` at the project root using the template in [template.md](template.md).
4. **Add one-line context** per table (what it stores, singleton pattern, etc.).
5. **Update** `docs/dir-tree.md` if it exists — add `db.md` entry when new.

## Section rules

| Section | Include when |
|---------|--------------|
| Overview | Always — engine, database name, migration/source path |
| Tables | Always — one `### table_name` per table |
| Enum Types | Custom enums exist |
| Indexes | Non-PK indexes exist |
| Relationships | FKs or logical links between tables |

## Table format

Each table section:

```markdown
### table_name

One-line purpose.

| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() |
```

- **Column** — exact DB name
- **Type** — DB type (`TEXT`, `UUID`, `history_type`, etc.)
- **Constraints** — PK, FK, UNIQUE, NOT NULL, DEFAULT, CHECK, nullable

Combine related constraints in one cell, comma-separated.

## Quality checks

- [ ] Every current table documented; dropped tables omitted
- [ ] Column names and types match migration/model source
- [ ] Enum values listed with short descriptions when known
- [ ] Indexes list name, table, and columns
- [ ] Relationships note FK vs logical link

## Additional resources

- Full output template: [template.md](template.md)
