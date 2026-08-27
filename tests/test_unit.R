library(cramerDBlite)

# --- .normalize_url -----------------------------------------------------------
stopifnot(
  # relative path appended to base
  cramerDBlite:::.normalize_url("seine/event/", "https://cramerdb.com/api/") ==
    "https://cramerdb.com/api/seine/event/",
  # multi-segment relative path
  cramerDBlite:::.normalize_url("biology/fish/", "https://cramerdb.com/api/") ==
    "https://cramerdb.com/api/biology/fish/",
  # relative path without trailing slash preserved
  cramerDBlite:::.normalize_url("seine/event", "https://cramerdb.com/api/") ==
    "https://cramerdb.com/api/seine/event",
  # leading slash stripped before resolution — appends to base correctly
  cramerDBlite:::.normalize_url("/seine/event/", "https://cramerdb.com/api/") ==
    "https://cramerdb.com/api/seine/event/",
  # base without trailing slash — slash added before resolution
  cramerDBlite:::.normalize_url("seine/event/", "https://cramerdb.com/api") ==
    "https://cramerdb.com/api/seine/event/",
  # absolute URL returned unchanged regardless of base
  cramerDBlite:::.normalize_url("https://other.com/api/", "https://cramerdb.com/api/") ==
    "https://other.com/api/",
  # http scheme also passes through unchanged
  cramerDBlite:::.normalize_url("http://cramerdb.com/api/", "https://cramerdb.com/api/") ==
    "http://cramerdb.com/api/"
)

# --- .nulls_to_na -------------------------------------------------------------
x <- list(a = 1, b = NULL, c = list())
r <- cramerDBlite:::.nulls_to_na(x)
stopifnot(is.na(r$b), is.na(r$c))

# --- .bind_rows ---------------------------------------------------------------
df1 <- data.frame(a = 1L, b = "x", stringsAsFactors = FALSE)
df2 <- data.frame(a = 2L, stringsAsFactors = FALSE)
r <- cramerDBlite:::.bind_rows(list(df1, df2))
stopifnot(nrow(r) == 2, ncol(r) == 2, is.na(r$b[2]))

# --- .chunk_indices -----------------------------------------------------------
chunks <- cramerDBlite:::.chunk_indices(5, 2)
stopifnot(length(chunks) == 3, identical(chunks[[3]], 5L))

# --- .join_url ----------------------------------------------------------------
stopifnot(
  cramerDBlite:::.join_url("https://cramerdb.com/api/seine/event/", 42) ==
    "https://cramerdb.com/api/seine/event/42/"
)

# --- .features_to_tbl ---------------------------------------------------------
feats <- list(
  list(type = "Feature", id = "1", geometry = NULL,
       properties = list(name = "Site A", value = 10)),
  list(type = "Feature", id = "2", geometry = NULL,
       properties = list(name = "Site B", value = NULL))
)
df <- cramerDBlite:::.features_to_tbl(feats)
stopifnot(is.data.frame(df), nrow(df) == 2, names(df)[1] == "id", is.na(df$value[2]))

# --- .as_row_list -------------------------------------------------------------
df <- data.frame(id = c(1L, NA_integer_), name = c("a", "b"), stringsAsFactors = FALSE)
rows <- cramerDBlite:::.as_row_list(df, "id")
stopifnot(length(rows) == 2, is.null(rows[[2]]$id))

# --- .check_url_trusted -------------------------------------------------------
cramerDBlite:::.check_url_trusted("https://cramerdb.com/api/sites/")
cramerDBlite:::.check_url_trusted("https://staging.cramerdb.com/api/sites/")

stopifnot(
  inherits(
    tryCatch(cramerDBlite:::.check_url_trusted("https://httpbin.org/"), error = identity),
    "error"
  )
)

old_opts <- options(cramerdb.allowed_hosts = "httpbin.org")
cramerDBlite:::.check_url_trusted("https://httpbin.org/")
cramerDBlite:::.check_url_trusted("https://cramerdb.com/api/")
options(old_opts)

# --- get_token / .get_token / .auth_headers -----------------------------------
stopifnot(
  inherits(tryCatch(get_token(), error = identity), "error")
)

old_opts <- options(cramerdb.token = NULL)
Sys.unsetenv("CRAMERDB_TOKEN")
stopifnot(is.null(cramerDBlite:::.get_token()))

options(cramerdb.token = "test-token-123")
stopifnot(
  identical(cramerDBlite:::.get_token(), "test-token-123"),
  identical(cramerDBlite:::.auth_headers()$Authorization, "Token test-token-123")
)
options(old_opts)

message("All unit tests passed.")
