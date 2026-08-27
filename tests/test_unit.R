library(cramerDBlite)

# --- .normalize_url -----------------------------------------------------------
stopifnot(
  # relative path appended to base
  cramerDBlite:::.normalize_url("seine/event/", "https://api.cramerdb.com/rest/") ==
    "https://api.cramerdb.com/rest/seine/event/",
  # multi-segment relative path
  cramerDBlite:::.normalize_url("biology/fish/", "https://api.cramerdb.com/rest/") ==
    "https://api.cramerdb.com/rest/biology/fish/",
  # relative path without trailing slash preserved
  cramerDBlite:::.normalize_url("seine/event", "https://api.cramerdb.com/rest/") ==
    "https://api.cramerdb.com/rest/seine/event",
  # leading slash stripped before resolution — appends to base correctly
  cramerDBlite:::.normalize_url("/seine/event/", "https://api.cramerdb.com/rest/") ==
    "https://api.cramerdb.com/rest/seine/event/",
  # base without trailing slash — slash added before resolution
  cramerDBlite:::.normalize_url("seine/event/", "https://api.cramerdb.com/rest") ==
    "https://api.cramerdb.com/rest/seine/event/",
  # absolute URL returned unchanged regardless of base -- .check_url_trusted,
  # not .normalize_url, is what rejects it
  cramerDBlite:::.normalize_url("https://other.com/api/", "https://api.cramerdb.com/rest/") ==
    "https://other.com/api/",
  cramerDBlite:::.normalize_url("http://api.cramerdb.com/rest/", "https://api.cramerdb.com/rest/") ==
    "http://api.cramerdb.com/rest/",
  # protocol-relative URL resolves under the base host rather than off-site
  cramerDBlite:::.normalize_url("//evil.example/x", "https://api.cramerdb.com/rest/") ==
    "https://api.cramerdb.com/rest/evil.example/x"
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
  cramerDBlite:::.join_url("https://api.cramerdb.com/rest/seine/event/", 42) ==
    "https://api.cramerdb.com/rest/seine/event/42/"
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
# a missing id is dropped entirely, not sent as "id": null
stopifnot(length(rows) == 2, is.null(rows[[2]]$id), !("id" %in% names(rows[[2]])))
# a missing non-key field keeps its name and is sent as an explicit null
df2 <- data.frame(id = 1L, name = NA_character_, stringsAsFactors = FALSE)
r2 <- cramerDBlite:::.as_row_list(df2, "id")
stopifnot("name" %in% names(r2[[1]]), is.null(r2[[1]]$name))

# --- .check_url_trusted -------------------------------------------------------
cramerDBlite:::.check_url_trusted("https://api.cramerdb.com/rest/sites/")
# host match is case-insensitive
cramerDBlite:::.check_url_trusted("https://API.CRAMERDB.COM/rest/")

errs <- function(expr) inherits(tryCatch(expr, error = identity), "error")

stopifnot(
  # untrusted host
  errs(cramerDBlite:::.check_url_trusted("https://httpbin.org/")),
  # another host in the same domain is not allowed by default
  errs(cramerDBlite:::.check_url_trusted("https://staging.cramerdb.com/rest/")),
  # https is required, even on an allowed host
  errs(cramerDBlite:::.check_url_trusted("http://api.cramerdb.com/rest/")),
  # userinfo cannot disguise the real host
  errs(cramerDBlite:::.check_url_trusted("https://api.cramerdb.com@evil.example/")),
  # a suffix of an allowed host is not an allowed host
  errs(cramerDBlite:::.check_url_trusted("https://api.cramerdb.com.evil.example/"))
)

# another deployment can be reached by adding its host
old_opts <- options(cramerdb.allowed_hosts = "staging.cramerdb.com")
cramerDBlite:::.check_url_trusted("https://staging.cramerdb.com/rest/")
cramerDBlite:::.check_url_trusted("https://api.cramerdb.com/rest/")
stopifnot(errs(cramerDBlite:::.check_url_trusted("http://staging.cramerdb.com/rest/")))
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

with_stub <- function(name, fn, expr) {
  ns <- asNamespace("cramerDBlite")
  orig <- get(name, envir = ns)
  unlockBinding(name, ns)
  assign(name, fn, envir = ns)
  on.exit({ assign(name, orig, envir = ns); lockBinding(name, ns) })
  force(expr)
}

# an off-host 'next' is rejected instead of being fetched with the token
with_stub(".fetch_once", stub_pages(list("https://evil.example/api/page2/")), {
  stopifnot(errs(cramerDBlite:::.fetch_pages("https://api.cramerdb.com/rest/x/",
                                             timeout = 1L, max_tries = 1L)))
})

# a self-referential 'next' stops instead of looping forever
with_stub(".fetch_once", stub_pages(list("https://api.cramerdb.com/rest/x/?page=2",
                                         "https://api.cramerdb.com/rest/x/?page=2")), {
  stopifnot(errs(cramerDBlite:::.fetch_pages("https://api.cramerdb.com/rest/x/",
                                             timeout = 1L, max_tries = 1L)))
})

# max_pages caps an endless but always-new sequence of 'next' links
endless <- local({
  n <- 0L
  function(url, headers = list(), labels = TRUE, timeout, max_tries) {
    n <<- n + 1L
    list(results = list(list(id = n)), count = 1e6L,
         `next` = sprintf("https://api.cramerdb.com/rest/x/?page=%d", n))
  }
})

with_stub(".fetch_once", endless, {
  pages <- withCallingHandlers(
    cramerDBlite:::.fetch_pages("https://api.cramerdb.com/rest/x/", timeout = 1L,
                                max_tries = 1L, max_pages = 4L),
    warning = function(w) invokeRestart("muffleWarning")
  )
  stopifnot(length(pages) == 4L)
})

# --- on_error -----------------------------------------------------------------
# Stub .send_json so no network is needed; count how many rows were attempted.
calls <- 0L
stub_send <- function(fail_on) {
  function(method, url, body, headers, timeout, max_tries) {
    calls <<- calls + 1L
    if (calls %in% fail_on) stop("HTTP 400 Bad Request", call. = FALSE)
    TRUE
  }
}

warns <- function(expr) inherits(tryCatch(expr, warning = identity), "warning")
muffled <- function(expr)
  withCallingHandlers(expr, warning = function(w) invokeRestart("muffleWarning"))

rows3 <- data.frame(name = c("a", "b", "c"), stringsAsFactors = FALSE)

# default: a rejected row aborts the batch, so later rows are never sent
calls <- 0L
with_stub(".send_json", stub_send(2L), {
  stopifnot(errs(create("x/", rows3)), calls == 2L)
})

# on_error = "continue": the rest of the batch runs and the failure is warned
calls <- 0L
with_stub(".send_json", stub_send(2L), {
  stopifnot(warns(create("x/", rows3, on_error = "continue")))
})
calls <- 0L
with_stub(".send_json", stub_send(2L), {
  stopifnot(identical(muffled(create("x/", rows3, on_error = "continue")), FALSE),
            calls == 3L)
})

# a clean batch still returns TRUE
calls <- 0L
with_stub(".send_json", stub_send(integer(0)), {
  stopifnot(identical(create("x/", rows3, on_error = "continue"), TRUE), calls == 3L)
})

# --- upsert: a 404 on PATCH falls back to POST --------------------------------
methods <- character(0)
stub_methods <- function(method, url, body, headers, timeout, max_tries) {
  methods <<- c(methods, method)
  method != "PATCH"   # PATCH answers 404, POST succeeds
}
with_stub(".send_json", stub_methods, {
  ok <- muffled(upsert("x/", data.frame(id = "abc", name = "a", stringsAsFactors = FALSE)))
  stopifnot(identical(methods, c("PATCH", "POST")), identical(ok, TRUE))
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
