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

# Run unit tests (source-based, not testthat)
source("tests/test_unit.R")
```

There is also an integration script at `inst/scripts/test_integration.R` that requires a live API token.

## Architecture

`cramerDBlite` is a thin R client over the CramerDB Django REST Framework API, defaulting to `https://cramerdb.com/api/`. All public functions accept a `base_url` parameter as an escape hatch; reaching another host also requires adding it to `getOption("cramerdb.allowed_hosts")`.

### File layout

- `R/auth.R` — token storage/retrieval: `set_token`/`get_token` (disabled, always error), `clear_token`. Token lookup priority: R options (`cramerdb.token`) → `CRAMERDB_TOKEN` env var, via internal `.get_token()`.
- `R/fetch.R` — `fetch()`, `whoami()`, and their pagination/normalization pipeline.
- `R/crud.R` — `create()`, `update()`, `upsert()`, and their HTTP helpers.
- `R/endpoints.R` — `endpoints()` and `fields()` for API discovery.
- `R/utils.R` — all shared internal helpers: `%||%`, `.normalize_url()`, `.check_url_trusted()`, `.add_headers()`, `.is_verbose()`, `.join_url()`.

### Key internal patterns

**Authentication**: `.auth_headers(headers)` is called at the top of every public function. It injects `Authorization: Token <token>` unless the caller already supplied an `Authorization` header.

**Security guard**: `.check_url_trusted(url)` is called after URL resolution in every public function. It rejects any host not in `c("cramerdb.com", "api.cramerdb.com")` plus `getOption("cramerdb.allowed_hosts")`. This prevents credential leakage when a user passes an arbitrary URL.

**URL normalization**: `.normalize_url(url, base_url)` prepends `base_url` to relative paths (uses `httr2::url_parse` with a `base_url` argument).

**fetch() pipeline**: `fetch()` → `.fetch_pages()` (handles DRF pagination via `next` links, prints progress when `verbose = TRUE`) → `.normalize_pages_to_df()` (dispatches to `.features_to_tbl()` for GeoJSON FeatureCollections or `.objects_to_tbl()` for plain JSON arrays). `fetch()` always returns a plain tibble/data.frame, never an `sf` object.

**CRUD pipeline**: Each of `create/update/upsert` serializes the input data frame with `.as_row_list()` (which also extracts lon/lat from `sf` geometries into `.lon`/`.lat` columns, and drops an NA `id_col` rather than sending `"id": null`), then iterates row-by-row calling `.post_one()` or `.patch_one()` through `.attempt()`. `chunk_size` controls progress message grouping only — each row is still one HTTP request. All three functions support a `dry_run = TRUE` flag that prints a preview of the first three records without sending any requests, and an `on_error = "continue"` flag that skips rejected rows, reports them via `.report_failures()`, and returns FALSE.

**sf / GeoJSON**: For writes, `create/update/upsert` auto-detect `inherits(data, "sf")` and serialize as GeoJSON Features (`style = "feature"`). The `sf` package is a `Suggests` dependency and loaded lazily.

**Verbosity**: `.is_verbose()` checks `getOption("cramerdb_verbose", FALSE)`. All progress output uses `message()`. Note the option name is `cramerdb_verbose` (underscore), not `cramerdb.verbose` (dot).
