#' Fetch any CramerDB endpoint into a data frame
#'
#' Follows DRF pagination automatically and normalizes both plain JSON arrays
#' and GeoJSON FeatureCollections into a `data.frame`.
#'
#' @param url Character. Full URL or relative path (e.g. `"tagging/event/"`).
#' @param headers Named list of additional HTTP headers.
#' @param base_url Character. Base API URL.
#' @param query Named list of query parameters appended to the URL.
#' @param verbose Logical. Print pagination progress. Defaults to
#'   `getOption("cramerdb_verbose", FALSE)`.
#' @param timeout Integer. Request timeout in seconds. Default 60.
#' @param max_tries Integer. Maximum retry attempts for transient errors (429, 503). Default 3.
#' @param max_pages Integer. Maximum pages to follow. Default 1000.
#' @return A `data.frame`.
#' @export
fetch <- function(url, headers = list(), base_url = "https://api.cramerdb.com/rest/",
                  query = list(),
                  verbose = getOption("cramerdb_verbose", FALSE),
                  timeout = 60L, max_tries = 3L, max_pages = 1000L) {
  headers  <- .auth_headers(headers)
  url      <- .normalize_url(url, base_url)
  .check_url_trusted(url)

  if (length(query) > 0) {
    query <- .prepare_query(query)
    url   <- do.call(httr2::req_url_query, c(list(httr2::request(url)), query))$url
  }

  .normalize_pages_to_df(.fetch_pages(url, headers, verbose = verbose,
                                      timeout = timeout, max_tries = max_tries,
                                      max_pages = max_pages))
}

#' Check who is authenticated
#'
#' @param base_url Character. Base API URL.
#' @param timeout Integer. Request timeout in seconds. Default 60.
#' @param max_tries Integer. Maximum retry attempts for transient errors (429, 503). Default 3.
#' @return Invisibly returns the parsed response list.
#' @export
whoami <- function(base_url = "https://api.cramerdb.com/rest/",
                   timeout = 60L, max_tries = 3L) {
  headers  <- .auth_headers(list())
  url      <- .normalize_url("", base_url)
  .check_url_trusted(url)
  res      <- .fetch_once(url, headers, labels = FALSE, timeout = timeout, max_tries = max_tries)
  message("Logged in as: ", .sanitize(res[["user"]]))
  invisible(res)
}

# ---- internals ---------------------------------------------------------------

.prepare_query <- function(query) {
  lapply(query, function(v) if (length(v) > 1) paste(v, collapse = ",") else v)
}

.has_query_param <- function(url, name) {
  grepl(paste0("(?i)([?&])", name, "(=|&|$)"), url, perl = TRUE)
}

.fetch_once <- function(url, headers = list(), labels = TRUE, timeout, max_tries) {
  req <- httr2::request(url)
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_options(req, followlocation = 0L)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- .add_headers(req, headers)
  if (isTRUE(labels) && !.has_query_param(url, "labels"))
    req <- do.call(httr2::req_url_query, c(list(req), list(labels = "1")))
  req <- httr2::req_retry(req, max_tries = max_tries,
                          is_transient = \(r) httr2::resp_status(r) %in% c(429L, 503L))
  res <- httr2::req_perform(req)
  .check_no_redirect(res)
  httr2::resp_check_status(res)
  httr2::resp_body_json(res, simplifyVector = FALSE)
}

.fetch_pages <- function(url, headers = list(), labels = TRUE, verbose = FALSE,
                         timeout, max_tries, max_pages = 1000L) {
  body <- .fetch_once(url, headers, labels = labels, timeout = timeout, max_tries = max_tries)

  if (!is.list(body) || is.null(body[["results"]])) return(list(body))

  pages      <- list(body)
  seen <- url
  nxt        <- body[["next"]]
  page_num   <- 2L
  total_count <- body[["count"]]
  page_size   <- length(body[["results"]])
  total_pages <- if (!is.null(total_count) && page_size > 0)
    ceiling(total_count / page_size) else NA_integer_

  if (!is.null(nxt) && nzchar(nxt) && verbose) {
    if (!is.na(total_pages))
      message(sprintf("Fetching %d pages (~%d records)", total_pages, total_count))
    else
      message("Fetching paginated data...")
  }

  while (!is.null(nxt) && is.character(nxt) && nzchar(nxt)) {
    .check_url_trusted(nxt)  # server-supplied link, and it carries the token
    if (nxt %in% seen)
      stop("Pagination loop: server returned a 'next' link already fetched.", call. = FALSE)
    if (length(pages) >= max_pages) {
      warning(sprintf("Stopped at max_pages = %d; more results remain.", max_pages),
              call. = FALSE)
      break
    }
    if (verbose) {
      if (!is.na(total_pages))
        message(sprintf("Page [%d/%d]", page_num, total_pages))
      else
        message(sprintf("Fetching page %d...", page_num))
    }
    seen <- c(seen, nxt)
    pg     <- .fetch_once(nxt, headers, labels = labels, timeout = timeout, max_tries = max_tries)
    pages  <- c(pages, list(pg))
    nxt    <- pg[["next"]]
    page_num <- page_num + 1L
  }

  pages
}

.is_feature <- function(x) {
  is.list(x) && identical(x[["type"]], "Feature") &&
    "geometry" %in% names(x) && !is.null(x[["properties"]])
}

.sanitize_nested <- function(val) {
  if (is.null(val) || length(val) == 0) return(NA)
  if (!is.list(val)) return(val)
  cleaned <- lapply(val, .sanitize_nested)
  names(cleaned) <- names(val)
  cleaned
}

.nulls_to_na <- function(x) {
  if (!is.list(x)) return(if (is.null(x)) NA else x)
  result <- lapply(x, function(val) {
    if (is.null(val) || length(val) == 0) return(NA)
    if (is.list(val) || length(val) > 1)  return(list(.sanitize_nested(val)))
    val
  })
  names(result) <- names(x)
  result
}

.bind_rows <- function(rows) {
  rows <- rows[!vapply(rows, is.null, logical(1L))]
  if (length(rows) == 0) return(data.frame())
  all_cols <- unique(unlist(lapply(rows, names)))

  cols <- lapply(all_cols, function(nm) {
    vals <- lapply(rows, function(df) if (nm %in% names(df)) df[[nm]] else NA)
    tryCatch(
      do.call(c, vals),
      error = function(e) as.character(vapply(vals, format, character(1L)))
    )
  })
  names(cols) <- all_cols

  result <- as.data.frame(cols, stringsAsFactors = FALSE)
  rownames(result) <- NULL
  result
}

.features_to_tbl <- function(features) {
  if (length(features) == 0) return(data.frame())
  rows <- lapply(features, function(f) {
    if (!.is_feature(f)) return(NULL)
    prop <- .nulls_to_na(f[["properties"]] %||% list())
    df   <- as.data.frame(prop, stringsAsFactors = FALSE)
    df$id <- as.character(f[["id"]] %||% NA_character_)
    df[c("id", setdiff(names(df), "id"))]
  })
  .bind_rows(rows)
}

.objects_to_tbl <- function(items) {
  if (length(items) == 0) return(data.frame())
  rows <- lapply(items, function(x) {
    as.data.frame(.nulls_to_na(x), stringsAsFactors = FALSE)
  })
  .bind_rows(rows)
}

.normalize_pages_to_df <- function(pages) {
  # DRF paginated
  if (length(pages) && is.list(pages[[1]]) && !is.null(pages[[1]][["results"]])) {
    all_results <- lapply(pages, `[[`, "results")

    # FeatureCollection inside results
    if (is.list(all_results[[1]]) && identical(all_results[[1]][["type"]], "FeatureCollection")) {
      feats <- unlist(lapply(all_results, function(r) r[["features"]] %||% list()),
                      recursive = FALSE)
      return(.features_to_tbl(feats))
    }

    items <- unlist(all_results, recursive = FALSE)
    if (length(items) > 0 && all(vapply(items, .is_feature, logical(1L))))
      return(.features_to_tbl(items))
    return(.objects_to_tbl(items))
  }

  # Single-page FeatureCollection
  if (length(pages) == 1 && identical(pages[[1]][["type"]], "FeatureCollection")) {
    return(.features_to_tbl(pages[[1]][["features"]] %||% list()))
  }

  # Single-page array
  if (length(pages) == 1 && is.list(pages[[1]]) &&
      (is.null(names(pages[[1]])) || all(names(pages[[1]]) == ""))) {
    items <- pages[[1]]
    if (length(items) > 0 && all(vapply(items, .is_feature, logical(1L))))
      return(.features_to_tbl(items))
    return(.objects_to_tbl(items))
  }

  # Single object
  as.data.frame(pages[[1]], stringsAsFactors = FALSE)
}
