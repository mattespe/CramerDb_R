#' @title Fetch any Cramer API endpoint into a tibble
#' @description
#' `fetch()` follows pagination automatically and normalizes both
#' plain JSON lists and GeoJSON FeatureCollections into a plain `tibble`.
#'
#' @param url Character. Full URL or relative path (e.g., "tagging/event/").
#'   Relative paths are prepended with base_url.
#' @param headers Named list of HTTP headers (e.g., list(Authorization = "Token xxx")).
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @return A `tibble`.
#' @export

fetch <- function(url, headers = list(), base_url = "https://cramerdb.com/api/",
                  staging = FALSE, query = list()) {
  headers  <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url      <- .normalize_url(url, base_url)

  if (length(query) > 0) {
    query <- .prepare_query(query)
    tmp   <- do.call(httr2::req_url_query, c(list(httr2::request(url)), query))
    url   <- tmp$url
  }

  pages <- .fetch_pages(url, headers)
  .normalize_pages_to_df(pages)
}

# ---- internals -------------------------------------------------------------

# Collapse vector values to CSV for Django __in lookups; leave scalars alone
.prepare_query <- function(query) {
  lapply(query, function(v) {
    if (length(v) > 1) paste(v, collapse = ",") else v
  })
}

.add_headers <- function(req, headers) {
  if (length(headers) > 0) {
    req <- do.call(httr2::req_headers, c(list(req), headers))
  }
  req
}

.add_query <- function(req, query) {
  if (length(query) > 0) {
    req <- do.call(httr2::req_url_query, c(list(req), query))
  }
  req
}

.has_query_param <- function(url, name) {
  patt <- paste0("(?i)([?&])", name, "(=|&|$)")
  grepl(patt, url, perl = TRUE)
}

.fetch_once <- function(url, headers = list(), labels = TRUE) {
  req <- httr2::request(url)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- .add_headers(req, headers)

  if (isTRUE(labels) && !.has_query_param(url, "labels")) {
    req <- .add_query(req, list(labels = "1"))
  }

  res <- httr2::req_perform(req)
  httr2::resp_check_status(res)
  httr2::resp_body_json(res, simplifyVector = FALSE)
}

.fetch_pages <- function(url, headers = list(), labels = TRUE) {
  body <- .fetch_once(url, headers, labels = labels)

  if (is.list(body) && !is.null(body[["results"]])) {
    pages <- list(body)
    nxt <- body[["next"]]

    if (!is.null(nxt) && is.character(nxt) && nzchar(nxt)) {
      page_num <- 2
      total_count <- body[["count"]]
      page_size <- length(body[["results"]])
      total_pages <- if (!is.null(total_count) && page_size > 0)
        ceiling(total_count / page_size) else NA_integer_

      if (.is_verbose()) {
        if (!is.na(total_pages)) {
          message("Fetching paginated data:",
              sprintf(" %d pages (~%d records)", total_pages, total_count))
        } else {
          message("Fetching paginated data...")
        }
      }

      while (!is.null(nxt) && is.character(nxt) && nzchar(nxt)) {
        if (.is_verbose()) {
          if (!is.na(total_pages)) {
            message(sprintf("Progress [%d/%d] %d%%", page_num, total_pages,
                            round(page_num / total_pages * 100)))
          } else {
            message(sprintf("  Fetching page %d...", page_num))
          }
        }

        pg <- .fetch_once(nxt, headers, labels = labels)
        pages <- c(pages, list(pg))
        nxt <- pg[["next"]]
        page_num <- page_num + 1
      }

      if (.is_verbose()) {
        message(sprintf("Fetched %d pages successfully", length(pages)))
      }
    }

    return(pages)
  }

  list(body)
}

# Check if object is a GeoJSON Feature
.is_feature <- function(x) {
  is.list(x) && identical(x[["type"]], "Feature") &&
    "geometry" %in% names(x) && !is.null(x[["properties"]])
}

# Replace NULLs and empty lists with NA; wrap multi-element vectors as list-columns
.nulls_to_na <- function(x) {
  if (!is.list(x)) return(if (is.null(x)) NA else x)
  purrr::imap(x, function(val, nm) {
    if (is.null(val)) return(NA)
    if (length(val) == 0) return(NA)
    if (is.list(val) || length(val) > 1) return(list(val))
    val
  })
}

# Convert GeoJSON Feature list to tibble
.features_to_tbl <- function(features) {
  if (length(features) == 0) return(tibble::tibble())

  rows <- purrr::map(features, function(f) {
    if (!.is_feature(f)) return(NULL)

    id <- f[["id"]]
    prop <- .nulls_to_na(f[["properties"]] %||% list())
    tb <- tibble::as_tibble(prop)
    tb$id <- as.character(id %||% NA_character_)
    dplyr::relocate(tb, id)
  })

  dplyr::bind_rows(rows)
}

# Convert plain objects to tibble
.objects_to_tbl <- function(items) {
  if (length(items) == 0) return(tibble::tibble())

  rows <- purrr::map(items, function(x) {
    tibble::as_tibble(.nulls_to_na(x))
  })

  # Harmonize column types (character vs logical)
  all_cols <- unique(unlist(purrr::map(rows, names)))

  for (nm in all_cols) {
    classes <- purrr::map_chr(rows, function(df) {
      if (!nm %in% names(df)) return(NA_character_)
      class(df[[nm]])[1]
    })

    if ("character" %in% classes && "logical" %in% classes) {
      rows <- purrr::map(rows, function(df) {
        if (nm %in% names(df) && is.logical(df[[nm]])) {
          df[[nm]] <- as.character(df[[nm]])
        }
        df
      })
    }
  }

  dplyr::bind_rows(rows)
}

# Main normalizer
.normalize_pages_to_df <- function(pages) {
  # Case 1: DRF paginated results
  if (length(pages) && is.list(pages[[1]]) && !is.null(pages[[1]][["results"]])) {
    all_results <- purrr::map(pages, ~ .x[["results"]])

    # FeatureCollection in results
    if (is.list(all_results[[1]]) && identical(all_results[[1]][["type"]], "FeatureCollection")) {
      feats <- purrr::map(all_results, ~ .x[["features"]] %||% list()) |> purrr::flatten()
      return(.features_to_tbl(feats))
    }

    # List of Features
    items <- purrr::flatten(all_results)
    if (length(items) > 0 && all(purrr::map_lgl(items, .is_feature))) {
      return(.features_to_tbl(items))
    }

    # Plain objects
    return(.objects_to_tbl(items))
  }

  # Case 2: Single-page FeatureCollection
  if (length(pages) == 1 && is.list(pages[[1]]) &&
      identical(pages[[1]][["type"]], "FeatureCollection")) {
    feats <- pages[[1]][["features"]] %||% list()
    return(.features_to_tbl(feats))
  }

  # Case 3: Single-page array
  if (length(pages) == 1 && is.list(pages[[1]]) &&
      (is.null(names(pages[[1]])) || all(names(pages[[1]]) == ""))) {
    items <- pages[[1]]
    if (length(items) > 0 && all(purrr::map_lgl(items, .is_feature))) {
      return(.features_to_tbl(items))
    }
    return(.objects_to_tbl(items))
  }

  # Case 4: Single object

  tibble::as_tibble(pages[[1]])
}

`%||%` <- function(a, b) if (is.null(a)) b else a

.resolve_base_url <- function(base_url, staging = FALSE) {
  if (isTRUE(staging)) "https://staging.cramerdb.com/api/" else base_url
}

.normalize_url <- function(url, base_url = "https://cramerdb.com/api/") {
  if (grepl("^https?://", url)) {
    return(url)
  }

  if (!grepl("/$", base_url)) {
    base_url <- paste0(base_url, "/")
  }

  url <- gsub("^/+", "", url)
  paste0(base_url, url)
}
