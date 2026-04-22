# -- Public API ---------------------------------------------------------------

#' Create new records via API (POST)
#' @param url Endpoint - full URL or relative path (e.g., "seine/event/" or "https://cramerdb.com/api/seine/event/")
#' @param data data.frame or sf tibble
#' @param headers named list of HTTP headers (e.g., list(Authorization = "Token ..."))
#' @param id_col primary key col (default "id"). If missing or NA, server may assign.
#' @param style "auto", "plain", or "feature" (GeoJSON Feature). "auto" picks "feature" for sf, else "plain".
#' @param chunk_size number of rows per request batch (each row is one request; chunking controls progress/messages)
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @param dry_run Logical. If TRUE, show what would be sent without actually sending. Useful for validation.
#' @export
create <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE, staging = FALSE) {
  # inject Authorization header from stored token (if any)
  headers <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url <- .normalize_url(url, base_url)

  style <- match.arg(style)
  style <- .pick_style(style, data)
  rows  <- .as_row_list(data, id_col)
  total_rows <- NROW(data)

  # Dry run mode
  if (dry_run) {
    .show_dry_run("CREATE", url, rows, total_rows)
    return(invisible(NULL))
  }

  # Show progress if multiple rows
  if (total_rows > 1 && .is_verbose()) {
    message("Creating records:",
        sprintf(" %d rows\n", total_rows))
  }

  current <- 0
  purrr::walk(.chunk_indices(total_rows, chunk_size), function(ix) {
    purrr::walk(ix, function(i) {
      .post_one(url, rows[[i]], headers, style)
      current <<- current + 1
      if (total_rows > 1 && .is_verbose()) {
        message(sprintf("Creating [%d/%d]", current, total_rows))
      }
    })
  })

  if (total_rows > 1 && .is_verbose()) {
    message(sprintf("Created %d records successfully", total_rows))
  }

  invisible(TRUE)
}


#' Update records via API (PATCH by id)
#' @param url Endpoint - full URL or relative path (e.g., "seine/event/" or "https://cramerdb.com/api/seine/event/")
#' @param data data.frame or sf tibble
#' @param headers named list of HTTP headers
#' @param id_col primary key col (default "id")
#' @param style "auto", "plain", or "feature"
#' @param chunk_size number of rows per request batch
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @param dry_run Logical. If TRUE, show what would be sent without actually sending. Useful for validation.
#' @export
update <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE, staging = FALSE) {
  headers <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url <- .normalize_url(url, base_url)

  style <- match.arg(style)
  style <- .pick_style(style, data)
  if (!id_col %in% names(data)) stop("update(): '", id_col, "' column is required.")

  # Count valid rows
  valid_rows <- sum(!is.na(data[[id_col]]) & data[[id_col]] != "")
  total_rows <- NROW(data)

  rows <- .as_row_list(data, id_col)

  # Dry run mode
  if (dry_run) {
    if (valid_rows < total_rows) {
      warning(sprintf("update(): %d rows with missing '%s' will be skipped",
                           total_rows - valid_rows, id_col))
    }
    .show_dry_run("UPDATE", url, rows, valid_rows)
    return(invisible(NULL))
  }

  if (valid_rows < total_rows && .is_verbose()) {
    warning(sprintf("update(): %d rows with missing '%s' will be skipped",
                         total_rows - valid_rows, id_col))
  }

  # Show progress if multiple rows
  if (total_rows > 1 && .is_verbose()) {
    message("Updating records:" ,
        sprintf(" %d rows\n", total_rows))
  }

  current <- 0
  purrr::walk(.chunk_indices(total_rows, chunk_size), function(ix) {
    purrr::walk(ix, function(i) {
      rid <- rows[[i]][[id_col]]
      if (!is.null(rid) && !is.na(rid) && nzchar(as.character(rid))) {
        .patch_one(.join_url(url, rid), rows[[i]], headers, style)
      }
      current <<- current + 1
      if (total_rows > 1 && .is_verbose()) {
        message("Updating ", round(current / total_rows))
      }
    })
  })

  if (total_rows > 1 && .is_verbose()) {
    message(sprintf("Updated %d records successfully", valid_rows))
  }

  invisible(TRUE)
}

#' Upsert records via API (PATCH if id present & exists; otherwise POST)
#' @param url Endpoint - full URL or relative path (e.g., "seine/event/" or "https://cramerdb.com/api/seine/event/")
#' @param data data.frame or sf tibble
#' @param headers named list of HTTP headers
#' @param id_col primary key col (default "id")
#' @param style "auto", "plain", or "feature"
#' @param chunk_size number of rows per request batch
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @param dry_run Logical. If TRUE, show what would be sent without actually sending. Useful for validation.
#' @export
upsert <- function(url, data, headers = list(), id_col = "id",
                   style = c("auto", "plain", "feature"), chunk_size = 200L,
                   base_url = "https://cramerdb.com/api/", dry_run = FALSE, staging = FALSE) {
  headers <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url <- .normalize_url(url, base_url)

  style <- match.arg(style)
  style <- .pick_style(style, data)
  rows <- .as_row_list(data, id_col)
  total_rows <- NROW(data)

  # Dry run mode
  if (dry_run) {
    .show_dry_run("UPSERT", url, rows, total_rows)
    return(invisible(NULL))
  }

  # Show progress if multiple rows
  if (total_rows > 1 && .is_verbose()) {
    message("Upserting records:",
        sprintf(" %d rows\n", total_rows))
  }

  current <- 0
  created <- 0
  updated <- 0

  purrr::walk(.chunk_indices(total_rows, chunk_size), function(ix) {
    purrr::walk(ix, function(i) {
      row <- rows[[i]]
      rid <- row[[id_col]]
      if (!is.null(rid) && !is.na(rid) && nzchar(as.character(rid))) {
        # Try PATCH; if 404, POST as create
        ok <- .try_patch(.join_url(url, rid), row, headers, style)
        if (ok) {
          updated <<- updated + 1
        } else {
          .post_one(url, row, headers, style)
          created <<- created + 1
        }
      } else {
        .post_one(url, row, headers, style)
        created <<- created + 1
      }
      current <<- current + 1
      if (total_rows > 1 && .is_verbose()) {
        message("Upserting", round(current / total_rows))
      }
    })
  })

  if (total_rows > 1 && .is_verbose()) {
    message(sprintf("Upserted %d records (created: %d, updated: %d)",
                         total_rows, created, updated))
  }

  invisible(TRUE)
}

# -- Internals ----------------------------------------------------------------

# choose payload style
.pick_style <- function(style, data) {
  if (style == "auto") {
    if (inherits(data, "sf")) "feature" else "plain"
  } else style
}

# turn data.frame rows into named lists; preserve id_col name/value
.as_row_list <- function(df, id_col = "id") {
  # Replace NULL-like with NA to avoid tibble issues; send as null in JSON later
  df <- .df_nulls_to_na(df)
  
  # If sf → split geometry (lon/lat) so we can build GeoJSON Feature
  if (inherits(df, "sf")) {
    geom <- sf::st_geometry(df)
    # Expecting POINT geometries for now
    coords <- suppressWarnings(sf::st_coordinates(geom))
    # coords may be empty/non-point; handle NA safely
    if (nrow(coords) == nrow(df) && ncol(coords) >= 2) {
      df$.lon <- coords[, 1]
      df$.lat <- coords[, 2]
    } else {
      df$.lon <- NA_real_
      df$.lat <- NA_real_
    }
    df <- sf::st_drop_geometry(df)
  }
  
  # rowwise → list of lists
  rows <- split(df, seq_len(nrow(df)))
  purrr::map(rows, function(x) {
    x <- lapply(x, function(v) if (is.na(v)) NULL else v)
    # simplify 1-row data.frame to named list of scalars
    purrr::list_flatten(x)
  })
}

# safe indices for chunking
.chunk_indices <- function(n, k) {
  if (n <= 0) return(list())
  starts <- seq(1L, n, by = k)
  ends   <- pmin(n, starts + k - 1L)
  Map(function(a,b) a:b, starts, ends)
}

# join base collection URL and id → detail URL (handles trailing slash)
.join_url <- function(base, id) {
  base <- as.character(base)
  id   <- utils::URLencode(as.character(id), reserved = TRUE)
  if (grepl("/$", base)) paste0(base, id, "/") else paste0(base, "/", id, "/")
}

# HTTP helpers
.add_headers <- function(req, headers) {
  if (length(headers) > 0) {
    req <- do.call(httr2::req_headers, c(list(req), headers))
  }
  req
}

.send_json <- function(method, url, body, headers) {
  req <- httr2::request(url)
  req <- .add_headers(req, headers)
  req <- httr2::req_method(req, method)
  # jsonlite: NAs → null; scalar lists → unboxed
  req <- httr2::req_body_json(req, data = body, auto_unbox = TRUE, digits = NA, null = "null")
  # Don't throw on HTTP errors - we'll handle them ourselves
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  res <- httr2::req_perform(req)
  status <- httr2::resp_status(res)
  # 2xx okay
  if (status >= 200 && status < 300) return(TRUE)
  # Pass through 404 to allow upsert fallback
  if (status == 404) return(FALSE)
  # Extract server error message for better debugging

  err_body <- tryCatch(
    httr2::resp_body_json(res, simplifyVector = TRUE),
    error = function(e) httr2::resp_body_string(res)
  )
  err_msg <- if (is.list(err_body)) {
    paste(names(err_body), unlist(err_body), sep = ": ", collapse = "\n  ")
  } else {
    as.character(err_body)
  }
  stop(sprintf("HTTP %d %s\n  %s", status, httr2::resp_status_desc(res), err_msg), call. = FALSE)
}

.post_one  <- function(url, row, headers, style) {
  payload <- .row_payload(row, style)
  .send_json("POST", url, payload, headers)
}

.patch_one <- function(url, row, headers, style) {
  payload <- .row_payload(row, style)
  .send_json("PATCH", url, payload, headers)
}

.try_patch <- function(url, row, headers, style) {
  tryCatch(.patch_one(url, row, headers, style),
           error = function(e) FALSE)
}

# Build the outgoing JSON object for one row
# plain:   {"field1":..., "field2":...}
# feature: {"type":"Feature","geometry":{...},"properties":{...},"id": "..."} (if id present)
.row_payload <- function(row, style = "plain") {
  if (identical(style, "feature")) {
    lon <- row[[".lon"]]; lat <- row[[".lat"]]
    props <- row
    props[[".lon"]] <- NULL; props[[".lat"]] <- NULL
    # keep id both at top-level and inside properties ONLY if you want (commonly servers ignore one)
    id_val <- props[["id"]]; # may be NULL
    # remove id from props if the server expects id at top-level only
    # props[["id"]] <- NULL
    
    geom <- NULL
    if (!is.null(lon) && !is.null(lat) && is.finite(lon) && is.finite(lat)) {
      geom <- list(type = "Point", coordinates = c(unname(lon), unname(lat)))
    }
    out <- list(
      type = "Feature",
      geometry = geom,
      properties = props
    )
    if (!is.null(id_val)) out$id <- id_val
    return(out)
  }
  
  # plain
  row[[".lon"]] <- NULL; row[[".lat"]] <- NULL
  row
}

# NULL→NA (shallow) for frames/lists to keep tibble happy upstream
.df_nulls_to_na <- function(x) {
  if (is.data.frame(x)) return(x)
  if (!is.list(x)) return(if (is.null(x)) NA else x)
  purrr::modify(x, ~ if (is.null(.x)) NA else .x)
}

# Normalize URL: if relative path, prepend base_url
.normalize_url <- function(url, base_url = "https://cramerdb.com/api/") {
  # Check if URL is already absolute (has scheme)
  if (grepl("^https?://", url)) {
    return(url)
  }

  # Relative path - prepend base_url
  # Ensure base_url ends with /
  if (!grepl("/$", base_url)) {
    base_url <- paste0(base_url, "/")
  }

  # Remove leading slash from path if present
  url <- gsub("^/+", "", url)

  paste0(base_url, url)
}

# Check if verbose output is enabled
.is_verbose <- function() {
  verbose <- getOption("cramerdb.verbose", default = NULL)
  if (is.null(verbose)) {
    # Default: verbose if interactive, quiet otherwise
    return(interactive())
  }
  isTRUE(verbose)
}

# Show dry-run preview
.show_dry_run <- function(operation, url, rows, total_rows) {
  message(sprintf("DRY RUN: %s Preview", operation))

  message("Operation: ", operation)
  message("Endpoint: ", url)
  message("Records: ", total_rows)

  # Show first few records
  preview_count <- min(3, total_rows)

  message("Preview of first ", preview_count, " record(s):")

  for (i in 1:preview_count) {
    message(sprintf("Record %d:", i))
    # Pretty print JSON
    json_str <- jsonlite::toJSON(rows[[i]], auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
    message(json_str, "\n", sep = "")
  }

  if (total_rows > preview_count) {
    message("\n", sprintf("... and %d more record(s)", total_rows - preview_count))
  }
  
  warning(sprintf("This was a DRY RUN - no data was sent to the API"))
  message("  Remove dry_run = TRUE to execute")

  invisible(NULL)
}
