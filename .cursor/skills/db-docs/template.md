# Database Schema

[One sentence: engine + app purpose. Source path, e.g. migrations live in `migrations/`.]

## Overview

| Item | Value |
|------|-------|
| Engine | [PostgreSQL 16 / SQL Server 2016 / etc.] |
| Database | `[database_name]` |
| Migrations | `[file names or "see models/"]` |

## Tables

### example_table

[One-line purpose.]

| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() |
| name | TEXT | NOT NULL, UNIQUE |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() |

## Enum Types

### enum_name

| Value | Description |
|-------|-------------|
| value_a | [Short description] |
| value_b | [Short description] |

## Indexes

| Index | Table | Columns |
|-------|-------|---------|
| idx_example_created | example_table | created_at DESC |

## Relationships

| From | To | Notes |
|------|----|-------|
| child.parent_id | parent.id | FK ON DELETE CASCADE |
