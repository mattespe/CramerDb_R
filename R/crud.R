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
#' @param staging Logical. If TRUE, routes requests to the staging server.
#' @param verbose Logical. Print per-row progress. Defaults to
#'   `getOption("cramerdb_verbose", FALSE)`.
#' @return Invisibly returns `TRUE`.
#' @export
create <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE,
                   staging = FALSE, verbose = getOption("cramerdb_verbose", FALSE)) {
  headers  <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url      <- .normalize_url(url, base_url)
  style    <- .pick_style(match.arg(style), data)
  rows     <- .as_row_list(data, id_col)
  n        <- length(rows)

  if (dry_run) { .show_dry_run("CREATE", url, rows, n); return(invisible(NULL)) }

  for (i in seq_len(n)) {
    .post_one(url, rows[[i]], headers, style)
    if (n > 1 && verbose) message(sprintf("Creating [%d/%d]", i, n))
  }
  if (n > 1 && verbose) message(sprintf("Created %d records", n))
  invisible(TRUE)
}

#' Update existing records via API (PATCH by id)
#' @inheritParams create
#' @return Invisibly returns `TRUE`.
#' @export
update <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE,
                   staging = FALSE, verbose = getOption("cramerdb_verbose", FALSE)) {
  if (!id_col %in% names(data))
    stop("update(): '", id_col, "' column is required.", call. = FALSE)

  headers  <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url      <- .normalize_url(url, base_url)
  style    <- .pick_style(match.arg(style), data)
  rows     <- .as_row_list(data, id_col)
  n        <- length(rows)
  valid    <- sum(vapply(rows, function(r) {
    rid <- r[[id_col]]; !is.null(rid) && !is.na(rid) && nzchar(as.character(rid))
  }, logical(1L)))

  if (valid < n) warning(sprintf("update(): %d rows with missing '%s' will be skipped",
                                 n - valid, id_col), call. = FALSE)

  if (dry_run) { .show_dry_run("UPDATE", url, rows, valid); return(invisible(NULL)) }

  for (i in seq_len(n)) {
    rid <- rows[[i]][[id_col]]
    if (!is.null(rid) && !is.na(rid) && nzchar(as.character(rid)))
      .patch_one(.join_url(url, rid), rows[[i]], headers, style)
    if (n > 1 && verbose) message(sprintf("Updating [%d/%d]", i, n))
  }
  if (n > 1 && verbose) message(sprintf("Updated %d records", valid))
  invisible(TRUE)
}

#' Upsert records via API (PATCH if id exists; POST otherwise)
#' @inheritParams create
#' @return Invisibly returns `TRUE`.
#' @export
upsert <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE,
                   staging = FALSE, verbose = getOption("cramerdb_verbose", FALSE)) {
  headers  <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url      <- .normalize_url(url, base_url)
  style    <- .pick_style(match.arg(style), data)
  rows     <- .as_row_list(data, id_col)
  n        <- length(rows)

  if (dry_run) { .show_dry_run("UPSERT", url, rows, n); return(invisible(NULL)) }

  created <- 0L; updated <- 0L
  for (i in seq_len(n)) {
    row <- rows[[i]]
    rid <- row[[id_col]]
    if (!is.null(rid) && !is.na(rid) && nzchar(as.character(rid))) {
      if (.try_patch(.join_url(url, rid), row, headers, style)) {
        updated <- updated + 1L
      } else {
        .post_one(url, row, headers, style)
        created <- created + 1L
      }
    } else {
      .post_one(url, row, headers, style)
      created <- created + 1L
    }
    if (n > 1 && verbose) message(sprintf("Upserting [%d/%d]", i, n))
  }
  if (n > 1 && verbose)
    message(sprintf("Upserted %d records (created: %d, updated: %d)", n, created, updated))
  invisible(TRUE)
}

# ---- internals ---------------------------------------------------------------

.pick_style <- function(style, data) {
  if (style == "auto") if (inherits(data, "sf")) "feature" else "plain" else style
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
    lapply(as.list(df[i, , drop = FALSE]), function(v) if (length(v) == 1 && is.na(v)) NULL else v)
  })
}

.chunk_indices <- function(n, k) {
  if (n <= 0) return(list())
  starts <- seq(1L, n, by = k)
  Map(function(a, b) a:b, starts, pmin(n, starts + k - 1L))
}

.send_json <- function(method, url, body, headers) {
  req <- httr2::request(url)
  req <- .add_headers(req, headers)
  req <- httr2::req_method(req, method)
  req <- httr2::req_body_json(req, data = body, auto_unbox = TRUE, digits = NA, null = "null")
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  res <- httr2::req_perform(req)
  status <- httr2::resp_status(res)
  if (status >= 200L && status < 300L) return(TRUE)
  if (status == 404L) return(FALSE)
  err_body <- tryCatch(httr2::resp_body_json(res, simplifyVector = TRUE),
                       error = function(e) httr2::resp_body_string(res))
  err_msg <- if (is.list(err_body))
    paste(names(err_body), unlist(err_body), sep = ": ", collapse = "\n  ")
  else
    as.character(err_body)
  stop(sprintf("HTTP %d %s\n  %s", status, httr2::resp_status_desc(res), err_msg), call. = FALSE)
}

.post_one  <- function(url, row, headers, style) .send_json("POST",  url, .row_payload(row, style), headers)
.patch_one <- function(url, row, headers, style) .send_json("PATCH", url, .row_payload(row, style), headers)
.try_patch <- function(url, row, headers, style) tryCatch(.patch_one(url, row, headers, style), error = function(e) FALSE)

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
    message(jsonlite::toJSON(rows[[i]], auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null"))
  }
  if (n > 3L) message(sprintf("... and %d more", n - 3L))
  invisible(NULL)
}
