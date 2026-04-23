#' Fetch any CramerDB endpoint into a data frame
#'
#' Follows DRF pagination automatically and normalizes both plain JSON arrays
#' and GeoJSON FeatureCollections into a `data.frame`.
#'
#' @param url Character. Full URL or relative path (e.g. `"tagging/event/"`).
#' @param headers Named list of additional HTTP headers.
#' @param base_url Character. Base API URL.
#' @param staging Logical. If TRUE, routes requests to the staging server.
#' @param query Named list of query parameters appended to the URL.
#' @param verbose Logical. Print pagination progress. Defaults to
#'   `getOption("cramerdb_verbose", FALSE)`.
#' @return A `data.frame`.
#' @export
fetch <- function(url, headers = list(), base_url = "https://cramerdb.com/api/",
                  staging = FALSE, query = list(),
                  verbose = getOption("cramerdb_verbose", FALSE)) {
  headers  <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url      <- .normalize_url(url, base_url)

  if (length(query) > 0) {
    query <- .prepare_query(query)
    url   <- do.call(httr2::req_url_query, c(list(httr2::request(url)), query))$url
  }

  .normalize_pages_to_df(.fetch_pages(url, headers, verbose = verbose))
}

#' Check who is authenticated
#'
#' @param base_url Character. Base API URL.
#' @param staging Logical. If TRUE, routes requests to the staging server.
#' @return Invisibly returns the parsed response list.
#' @export
whoami <- function(base_url = "https://cramerdb.com/api/", staging = FALSE) {
  headers  <- .auth_headers(list())
  base_url <- .resolve_base_url(base_url, staging)
  url      <- .normalize_url("users/me/", base_url)
  res      <- .fetch_once(url, headers, labels = FALSE)
  message("Logged in as: ", res[["username"]] %||% res[["email"]] %||% "(unknown)")
  invisible(res)
}

# ---- internals ---------------------------------------------------------------

.prepare_query <- function(query) {
  lapply(query, function(v) if (length(v) > 1) paste(v, collapse = ",") else v)
}

.has_query_param <- function(url, name) {
  grepl(paste0("(?i)([?&])", name, "(=|&|$)"), url, perl = TRUE)
}

.fetch_once <- function(url, headers = list(), labels = TRUE) {
  req <- httr2::request(url)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- .add_headers(req, headers)
  if (isTRUE(labels) && !.has_query_param(url, "labels"))
    req <- do.call(httr2::req_url_query, c(list(req), list(labels = "1")))
  res <- httr2::req_perform(req)
  httr2::resp_check_status(res)
  httr2::resp_body_json(res, simplifyVector = FALSE)
}

.fetch_pages <- function(url, headers = list(), labels = TRUE, verbose = FALSE) {
  body <- .fetch_once(url, headers, labels = labels)

  if (!is.list(body) || is.null(body[["results"]])) return(list(body))

  pages      <- list(body)
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
    if (verbose) {
      if (!is.na(total_pages))
        message(sprintf("Page [%d/%d]", page_num, total_pages))
      else
        message(sprintf("Fetching page %d...", page_num))
    }
    pg     <- .fetch_once(nxt, headers, labels = labels)
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

.nulls_to_na <- function(x) {
  if (!is.list(x)) return(if (is.null(x)) NA else x)
  result <- lapply(x, function(val) {
    if (is.null(val) || length(val) == 0) return(NA)
    if (is.list(val) || length(val) > 1)  return(list(val))
    val
  })
  names(result) <- names(x)
  result
}

.bind_rows <- function(rows) {
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0) return(data.frame())
  all_cols <- unique(unlist(lapply(rows, names)))

  # coerce logical → character when the same column is character in other rows
  for (nm in all_cols) {
    classes <- vapply(rows, function(df) {
      if (nm %in% names(df)) class(df[[nm]])[1L] else NA_character_
    }, character(1L))
    if ("character" %in% classes && any(classes == "logical", na.rm = TRUE)) {
      rows <- lapply(rows, function(df) {
        if (nm %in% names(df) && is.logical(df[[nm]])) df[[nm]] <- as.character(df[[nm]])
        df
      })
    }
  }

  # fill missing columns with NA then rbind
  rows <- lapply(rows, function(df) {
    missing <- setdiff(all_cols, names(df))
    if (length(missing)) df[missing] <- NA
    df[all_cols]
  })
  result <- do.call(rbind, rows)
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
