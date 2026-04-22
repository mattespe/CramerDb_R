# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```r
# Load package during development (from within R, project root)
devtools::load_all()

# Generate documentation from roxygen2 comments
devtools::document()

# Run R CMD CHECK
devtools::check()

# Install dependencies
pak::pak()
```

There are no automated tests in this package yet.

## Architecture

`cramerdb` is a thin R client over the CramerDB Django REST Framework API at `https://cramerdb.com/api/`. All public functions accept a `base_url` and `staging` parameter as an escape hatch.

### File layout

- `R/auth.R` — token storage/retrieval (`set_token`, `get_token`, `clear_token`, `whoami`). Token lookup priority: R options → system keyring (`keyring` package, optional) → `CRAMERDB_TOKEN` env var.
- `R/fetch.R` — `fetch()` and its pagination/normalization pipeline.
- `R/crud.R` — `create()`, `update()`, `upsert()` and their HTTP helpers.
- `R/list.R` — `endpoints()`, `fields()`, `whoami()`, `browse_endpoints()`.
- `R/helpers.R` — `test_connection()`, `browse_endpoints()`, shared `.is_verbose()`.
- `R/zzz.R` — `.onAttach` startup message + update check.

### Key internal patterns

**Authentication**: `.auth_headers(headers)` is called at the top of every public function. It injects `Authorization: Token <token>` unless the caller already supplied an `Authorization` header.

**URL normalization**: `.normalize_url(url, base_url)` prepends `base_url` to relative paths. `.resolve_base_url(base_url, staging)` swaps in the staging host when `staging = TRUE`.

**fetch() pipeline**: `fetch()` → `.fetch_pages()` (handles DRF pagination via `next` links) → `.normalize_pages_to_df()` (dispatches to `.features_to_tbl()` for GeoJSON FeatureCollections or `.objects_to_tbl()` for plain JSON arrays).

**CRUD pipeline**: Each of `create/update/upsert` serializes the input data frame with `.as_row_list()` (which also extracts lon/lat from `sf` geometries into `.lon`/`.lat` columns), then iterates row-by-row calling `.post_one()` or `.patch_one()`. Batching via `chunk_size` controls progress messaging, not the HTTP calls (each row is still one request).

**sf / GeoJSON**: `fetch()` returns a plain tibble (not sf) even for GeoJSON endpoints — the README mentions an `as_sf` parameter but it is not implemented. For writes, `create/update/upsert` auto-detect `inherits(data, "sf")` and serialize as GeoJSON Features (`style = "feature"`).

**Verbosity**: `.is_verbose()` returns `interactive()` by default; override with `options(cramerdb.verbose = TRUE/FALSE)`. All progress output uses `message()` so it can be suppressed with `suppressMessages()`.

### Known issues in the codebase

- Several internal helpers (`.add_headers`, `.normalize_url`, `.build_endpoint_url`, `.is_verbose`) are defined redundantly in multiple files. The last-loaded definition wins at runtime.
- `crud.R` line 44 has a syntax error in the progress message: `message("Creating " round(...))` is missing a paste/sprintf call — `create()` will error on multi-row inputs in verbose mode.
- `fetch.R`'s `.fetch_pages()` references `current` and `total` variables in the progress branch that are never assigned, so pagination progress messages will error.
- The `%||%` null-coalescing operator is defined at the bottom of `fetch.R` and is used package-wide; it is not exported.
