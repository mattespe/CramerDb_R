#' Create new records via API (POST)
#' @param url Endpoint - full URL or relative path (e.g. `"seine/event/"`).
#' @param data `data.frame` or `sf` object.
#' @param headers Named list of additional HTTP headers.
#' @param id_col Name of the primary key column (default `"id"`).
#' @param style `"auto"`, `"plain"`, or `"feature"` (GeoJSON). `"auto"` picks
#'   `"feature"` for `sf` objects, `"plain"` otherwise.
#' @param chunk_size Controls progress message grouping (each row is still one request).
#' @param base_url Character. Base API URL.
#' @param dry_run Logical. Preview what would be sent without sending.
#' @param verbose Logical. Print per-chunk progress. Defaults to
#'   `getOption("cramerdb_verbose", FALSE)`.
#' @param timeout Integer. Request timeout in seconds. Default 60.
#' @param max_tries Integer. Maximum retry attempts for transient errors (429, 503). Default 3.
#' @param on_error `"stop"` (default) or `"continue"`; whether a row the server
#'   rejects aborts the batch or is skipped and reported in a warning.
#' @return Invisibly returns `TRUE`, or `FALSE` when `on_error = "continue"`
#'   and some rows failed.
#' @export
create <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE,
                   verbose = getOption("cramerdb_verbose", FALSE),
                   timeout = 60L, max_tries = 3L,
                   on_error = c("stop", "continue")) {
  if (!is.data.frame(data))
    stop("'data' must be a data.frame or sf object.", call. = FALSE)
  on_error = match.arg(on_error)
  headers  <- .auth_headers(headers)
  url      <- .normalize_url(url, base_url)
  .check_url_trusted(url)
  style    <- .pick_style(match.arg(style), data)
  rows     <- .as_row_list(data, id_col)
  n        <- length(rows)

  if (dry_run) { .show_dry_run("CREATE", url, rows, n); return(invisible(TRUE)) }

  failures = list()
  for (chunk in .chunk_indices(n, chunk_size)) {
    for (i in chunk) {
      res = .attempt(.post_one(url, rows[[i]], headers, style, timeout, max_tries), on_error)
      if (!res$ok) failures[[as.character(i)]] = res$message
    }
    if (n > 1 && verbose) message(sprintf("Creating [%d/%d]", max(chunk), n))
  }
  if (n > 1 && verbose) message(sprintf("Created %d records", n - length(failures)))
  .report_failures("create", n, failures)
  invisible(length(failures) == 0L)
}

#' Update existing records via API (PATCH by id)
#' @inheritParams create
#' @return Invisibly returns `TRUE`, or `FALSE` when `on_error = "continue"`
#'   and some rows failed.
#' @export
update <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE,
                   verbose = getOption("cramerdb_verbose", FALSE),
                   timeout = 60L, max_tries = 3L,
                   on_error = c("stop", "continue")) {
  if (!is.data.frame(data))
    stop("'data' must be a data.frame or sf object.", call. = FALSE)
  if (!id_col %in% names(data))
    stop("update(): '", id_col, "' column is required.", call. = FALSE)

  on_error = match.arg(on_error)
  headers  <- .auth_headers(headers)
  url      <- .normalize_url(url, base_url)
  .check_url_trusted(url)
  style    <- .pick_style(match.arg(style), data)
  rows     <- .as_row_list(data, id_col)
  n        <- length(rows)
  valid    <- sum(vapply(rows, function(r) {
    rid <- r[[id_col]]; !is.null(rid) && !is.na(rid) && nzchar(as.character(rid))
  }, logical(1L)))

  if (valid < n) warning(sprintf("update(): %d rows with missing '%s' will be skipped",
                                 n - valid, id_col), call. = FALSE)

  if (dry_run) { .show_dry_run("UPDATE", url, rows, valid); return(invisible(TRUE)) }

  patched = 0L
  failures = list()
  for (chunk in .chunk_indices(n, chunk_size)) {
    for (i in chunk) {
      rid <- rows[[i]][[id_col]]
      if (!is.null(rid) && !is.na(rid) && nzchar(as.character(rid))) {
        res = .attempt(.patch_one(.join_url(url, rid), rows[[i]], headers, style,
                                  timeout, max_tries), on_error)
        if (res$ok) patched = patched + 1L else failures[[as.character(i)]] = res$message
      }
    }
    if (n > 1 && verbose) message(sprintf("Updating [%d/%d]", patched, valid))
  }
  if (n > 1 && verbose) message(sprintf("Updated %d records", patched))
  .report_failures("update", valid, failures)
  invisible(length(failures) == 0L)
}

#' Upsert records via API (PATCH if id exists; POST otherwise)
#'
#' A record whose id is not found is created instead. The API answers "no
#' such record" and "that record is not yours to see" with the same 404
#' status. A record you lack permission on therefore looks identical to one
#' that does not exist, and creating it duplicates the original instead of
#' updating it. Rows that hit this case are reported in a warning. Set
#' `on_missing = "error"` to stop on them instead.
#'
#' @inheritParams create
#' @param on_missing `"create"` (default) or `"error"`; what to do when an id
#'   returns 404.
#' @return Invisibly returns `TRUE`, or `FALSE` when `on_error = "continue"`
#'   and some rows failed.
#' @export
upsert <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE,
                   verbose = getOption("cramerdb_verbose", FALSE),
                   timeout = 60L, max_tries = 3L,
                   on_missing = c("create", "error"),
                   on_error = c("stop", "continue")) {
  if (!is.data.frame(data))
    stop("'data' must be a data.frame or sf object.", call. = FALSE)
  on_missing <- match.arg(on_missing)
  on_error = match.arg(on_error)
  headers  <- .auth_headers(headers)
  url      <- .normalize_url(url, base_url)
  .check_url_trusted(url)
  style    <- .pick_style(match.arg(style), data)
  rows     <- .as_row_list(data, id_col)
  n        <- length(rows)

  if (dry_run) { .show_dry_run("UPSERT", url, rows, n); return(invisible(TRUE)) }

  created = 0L; updated = 0L; missing = character(0); failures = list()
  for (chunk in .chunk_indices(n, chunk_size)) {
    for (i in chunk) {
      res = .attempt(.upsert_one(url, rows[[i]], id_col, headers, style,
                                 timeout, max_tries, on_missing), on_error)
      if (!res$ok) {
        failures[[as.character(i)]] = res$message
        next
      }
      if (identical(res$value, "updated")) updated = updated + 1L else created = created + 1L
      if (identical(res$value, "recreated"))
        missing = c(missing, as.character(rows[[i]][[id_col]]))
    }
    if (n > 1 && verbose) message(sprintf("Upserting [%d/%d]", max(chunk), n))
  }
  if (length(missing)) {
    shown <- missing[seq_len(min(5L, length(missing)))]
    warning(sprintf(
      paste0("upsert(): %d row(s) supplied a '%s' that returned 404 and were created as new records (%s).\n",
             "  A 404 also means the record exists but is not visible to your account, in which case this duplicated it.\n",
             "  Use on_missing = \"error\" to stop on these instead."),
      length(missing), id_col, paste(shown, collapse = ", ")), call. = FALSE)
  }
  if (n > 1 && verbose)
    message(sprintf("Upserted %d records (created: %d, updated: %d)",
                    created + updated, created, updated))
  .report_failures("upsert", n, failures)
  invisible(length(failures) == 0L)
}

# ---- internals ---------------------------------------------------------------

.pick_style <- function(style, data) {
  if (style == "auto") if (inherits(data, "sf")) "feature" else "plain" else style
}

# PATCH when the id is present, POST when it is absent or the server answers
# 404. "recreated" = an id that 404'd and was posted as a new record.
.upsert_one = function(url, row, id_col, headers, style, timeout, max_tries, on_missing)
{
  rid = row[[id_col]]
  if (is.null(rid) || is.na(rid) || !nzchar(as.character(rid))) {
    .post_one(url, row, headers, style, timeout, max_tries)
    return("created")
  }
  if (.patch_one(.join_url(url, rid), row, headers, style, timeout, max_tries))
    return("updated")
  if (identical(on_missing, "error"))
    stop(sprintf("upsert(): %s '%s' returned 404; it is missing or not visible to your account.",
                 id_col, as.character(rid)), call. = FALSE)
  .post_one(url, row, headers, style, timeout, max_tries)
  "recreated"
}

# Run one row's request; under "continue" its error is captured so the rest of
# the batch still runs. `expr` is a promise, forced inside the chosen branch.
.attempt = function(expr, on_error)
{
  if (identical(on_error, "stop")) return(list(ok = TRUE, value = expr))
  tryCatch(list(ok = TRUE, value = expr),
           error = function(e) list(ok = FALSE, message = conditionMessage(e)))
}

.report_failures = function(verb, n, failures)
{
  if (!length(failures)) return(invisible(NULL))
  shown = failures[seq_len(min(5L, length(failures)))]
  warning(sprintf("%s(): %d of %d row(s) failed and were skipped:\n  %s",
                  verb, length(failures), n,
                  paste(sprintf("row %s: %s", names(shown), unlist(shown)),
                        collapse = "\n  ")),
          call. = FALSE)
  invisible(NULL)
}

.as_row_list <- function(df, id_col = "id") {
  if (inherits(df, "sf")) {
    if (!requireNamespace("sf", quietly = TRUE))
      stop("Package 'sf' is required to send sf objects.", call. = FALSE)
    geom   <- sf::st_geometry(df)
    coords <- suppressWarnings(sf::st_coordinates(geom))
    df$.lon <- if (nrow(coords) == nrow(df) && ncol(coords) >= 2) coords[, 1] else NA_real_
    df$.lat <- if (nrow(coords) == nrow(df) && ncol(coords) >= 2) coords[, 2] else NA_real_
    df <- sf::st_drop_geometry(df)
  }
  lapply(seq_len(nrow(df)), function(i) {
    row = lapply(as.list(df[i, , drop = FALSE]),
                 function(v) if (length(v) == 1 && is.na(v)) NULL else v)
    # a key has no null form; drop it so the server assigns one (other NA
    # fields still go out as explicit JSON nulls)
    if (id_col %in% names(row) && is.null(row[[id_col]])) row[[id_col]] = NULL
    row
  })
}

.chunk_indices <- function(n, k) {
  if (n <= 0) return(list())
  starts <- seq(1L, n, by = k)
  Map(function(a, b) a:b, starts, pmin(n, starts + k - 1L))
}

.send_json <- function(method, url, body, headers, timeout, max_tries) {
  req <- httr2::request(url)
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_options(req, followlocation = 0L)
  req <- .add_headers(req, headers)
  req <- httr2::req_method(req, method)
  req <- httr2::req_body_json(req, data = body, auto_unbox = TRUE, digits = NA, null = "null")
  req <- httr2::req_retry(req, max_tries = max_tries,
                          is_transient = \(r) httr2::resp_status(r) %in% c(429L, 503L))
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  res <- httr2::req_perform(req)
  .check_no_redirect(res)
  status <- httr2::resp_status(res)
  if (status >= 200L && status < 300L) return(TRUE)
  if (status == 404L) return(FALSE)
  err_body <- tryCatch(httr2::resp_body_json(res, simplifyVector = TRUE),
                       error = function(e) httr2::resp_body_string(res))
  err_msg <- if (is.list(err_body))
    paste(names(err_body), unlist(err_body), sep = ": ", collapse = "\n  ")
  else
    as.character(err_body)
  stop(sprintf("HTTP %d %s\n  %s", status, httr2::resp_status_desc(res),
               .sanitize(err_msg)), call. = FALSE)
}

.post_one  <- function(url, row, headers, style, timeout, max_tries)
  .send_json("POST",  url, .row_payload(row, style), headers, timeout, max_tries)
.patch_one <- function(url, row, headers, style, timeout, max_tries)
  .send_json("PATCH", url, .row_payload(row, style), headers, timeout, max_tries)

.row_payload <- function(row, style = "plain") {
  if (identical(style, "feature")) {
    lon <- row[[".lon"]]; lat <- row[[".lat"]]
    props <- row; props[[".lon"]] <- NULL; props[[".lat"]] <- NULL
    id_val <- props[["id"]]
    geom <- if (!is.null(lon) && !is.null(lat) && is.finite(lon) && is.finite(lat))
      list(type = "Point", coordinates = c(unname(lon), unname(lat))) else NULL
    out <- list(type = "Feature", geometry = geom, properties = props)
    if (!is.null(id_val)) out$id <- id_val
    return(out)
  }
  row[[".lon"]] <- NULL; row[[".lat"]] <- NULL
  row
}

.show_dry_run <- function(operation, url, rows, n) {
  message(sprintf("DRY RUN: %s -- %s (%d records)", operation, url, n))
  for (i in seq_len(min(3L, n))) {
    message(sprintf("Record %d:", i))
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      message(jsonlite::toJSON(rows[[i]], auto_unbox = TRUE, pretty = TRUE,
                               digits = NA, null = "null"))
    } else {
      message(paste(
        mapply(function(k, v) sprintf("  %s: %s", k, format(v)),
               names(rows[[i]]), rows[[i]]),
        collapse = "\n"
      ))
    }
  }
  if (n > 3L) message(sprintf("... and %d more", n - 3L))
  invisible(NULL)
}
