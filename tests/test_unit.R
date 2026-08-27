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
  # absolute URL returned unchanged regardless of base -- .check_url_trusted,
  # not .normalize_url, is what rejects it
  cramerDBlite:::.normalize_url("https://other.com/api/", "https://cramerdb.com/api/") ==
    "https://other.com/api/",
  cramerDBlite:::.normalize_url("http://cramerdb.com/api/", "https://cramerdb.com/api/") ==
    "http://cramerdb.com/api/",
  # protocol-relative URL resolves under the base host rather than off-site
  cramerDBlite:::.normalize_url("//evil.example/x", "https://cramerdb.com/api/") ==
    "https://cramerdb.com/api/evil.example/x"
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
# host match is case-insensitive
cramerDBlite:::.check_url_trusted("https://CRAMERDB.COM/api/")

errs <- function(expr) inherits(tryCatch(expr, error = identity), "error")

stopifnot(
  # untrusted host
  errs(cramerDBlite:::.check_url_trusted("https://httpbin.org/")),
  # https is required, even on an allowed host
  errs(cramerDBlite:::.check_url_trusted("http://cramerdb.com/api/")),
  # userinfo cannot disguise the real host
  errs(cramerDBlite:::.check_url_trusted("https://cramerdb.com@evil.example/")),
  # a suffix of an allowed host is not an allowed host
  errs(cramerDBlite:::.check_url_trusted("https://cramerdb.com.evil.example/"))
)

old_opts <- options(cramerdb.allowed_hosts = "httpbin.org")
cramerDBlite:::.check_url_trusted("https://httpbin.org/")
cramerDBlite:::.check_url_trusted("https://cramerdb.com/api/")
stopifnot(errs(cramerDBlite:::.check_url_trusted("http://httpbin.org/")))
options(old_opts)

# --- .fetch_pages: the server-supplied 'next' link is not trusted -------------
# Stub .fetch_once so no network is needed.
stub_pages <- function(nexts) {
  i <- 0L
  function(url, headers = list(), labels = TRUE, timeout, max_tries) {
    i <<- i + 1L
    list(results = list(list(id = i)), count = 99L, `next` = nexts[[min(i, length(nexts))]])
  }
}

with_stub <- function(fn, expr) {
  ns <- asNamespace("cramerDBlite")
  orig <- get(".fetch_once", envir = ns)
  unlockBinding(".fetch_once", ns)
  assign(".fetch_once", fn, envir = ns)
  on.exit({ assign(".fetch_once", orig, envir = ns); lockBinding(".fetch_once", ns) })
  force(expr)
}

# an off-host 'next' is rejected instead of being fetched with the token
with_stub(stub_pages(list("https://evil.example/api/page2/")), {
  stopifnot(errs(cramerDBlite:::.fetch_pages("https://cramerdb.com/api/x/",
                                             timeout = 1L, max_tries = 1L)))
})

# a self-referential 'next' stops instead of looping forever
with_stub(stub_pages(list("https://cramerdb.com/api/x/?page=2",
                          "https://cramerdb.com/api/x/?page=2")), {
  stopifnot(errs(cramerDBlite:::.fetch_pages("https://cramerdb.com/api/x/",
                                             timeout = 1L, max_tries = 1L)))
})

# max_pages caps an endless but always-new sequence of 'next' links
endless <- local({
  n <- 0L
  function(url, headers = list(), labels = TRUE, timeout, max_tries) {
    n <<- n + 1L
    list(results = list(list(id = n)), count = 1e6L,
         `next` = sprintf("https://cramerdb.com/api/x/?page=%d", n))
  }
})

with_stub(endless, {
  pages <- withCallingHandlers(
    cramerDBlite:::.fetch_pages("https://cramerdb.com/api/x/", timeout = 1L,
                                max_tries = 1L, max_pages = 4L),
    warning = function(w) invokeRestart("muffleWarning")
  )
  stopifnot(length(pages) == 4L)
})

# --- .sanitize ----------------------------------------------------------------
stopifnot(identical(cramerDBlite:::.sanitize("ok\033[2Jwiped"), "ok[2Jwiped"))

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

# clear_token() must clear the env var too, not just the option
Sys.setenv(CRAMERDB_TOKEN = "env-token-456")
suppressMessages(clear_token())
stopifnot(is.null(cramerDBlite:::.get_token()))
options(old_opts)

message("All unit tests passed.")
