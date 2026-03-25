#' @title List available API endpoints
#' @description
#' Navigate the CramerDB API tree structure by listing available endpoints.
#' Use `whoami()` to check authentication status.
#'
#' @param path Character. Optional API path segment (e.g., "seine", "biology").
#'   If NULL or missing, lists the root API endpoints.
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @param headers Named list of HTTP headers (e.g., list(Authorization = "Token xxx"))
#' @return Invisibly returns the parsed JSON response; prints formatted output
#' @export
#' @examples
#' \dontrun{
#' # List top-level endpoints
#' endpoints()
#'
#' # List endpoints for a specific section
#' endpoints("seine")
#' endpoints("biology")
#'
#' # Equivalent to:
#' endpoints("biology/some-sub-path")
#' }
endpoints <- function(path = NULL, base_url = "https://cramerdb.com/api/", headers = list(), staging = FALSE) {
  headers <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)

  # Build the full URL
  url <- .build_endpoint_url(base_url, path)

  # Fetch the endpoint info
  tryCatch({
    req <- httr2::request(url)
    # Add Accept header to ensure JSON response
    req <- httr2::req_headers(req, Accept = "application/json")
    req <- .add_headers(req, headers)
    res <- httr2::req_perform(req)
    httr2::resp_check_status(res)
    body <- httr2::resp_body_json(res, simplifyVector = FALSE)

    # Determine endpoint structure
    # Root endpoints have "endpoints" key, sub-endpoints are flat objects
    endpoints <- if (!is.null(body[["endpoints"]])) {
      body[["endpoints"]]
    } else {
      # Filter out non-endpoint keys (authenticated, user, etc.)
      body[!names(body) %in% c("authenticated", "user")]
    }

    if (is.list(endpoints) && length(endpoints) > 0) {
      # Sort endpoints alphabetically
      endpoint_names <- names(endpoints)
      endpoint_names <- endpoint_names[order(endpoint_names)]

      # Display header
      message(sprintf("Available endpoints at %s", url))

      # Display each endpoint with styling
      for (name in endpoint_names) {
        endpoint_url <- endpoints[[name]]

        # Style the endpoint name
        styled_name <- sprintf("  %-20s", name)

        message(styled_name, " ", endpoint_url)
      }
    } else {
      warning(sprintf("No endpoints available at %s", url))
    }

    invisible(body)

  }, error = function(e) {
    message(sprintf("Error fetching %s", url))
    message("  ", conditionMessage(e))
    invisible(NULL)
  })
}

#' @title Check authentication status
#' @description
#' Check if you are authenticated with the CramerDB API and see which user
#' you are logged in as.
#'
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @param headers Named list of HTTP headers (e.g., list(Authorization = "Token xxx"))
#' @return Invisibly returns the parsed JSON response; prints formatted output
#' @export
#' @examples
#' \dontrun{
#' # Check authentication status
#' whoami()
#'
#' # After setting token
#' set_token("your_token_here")
#' whoami()
#' }
whoami <- function(base_url = "https://cramerdb.com/api/", headers = list(), staging = FALSE) {
  headers <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)

  # Fetch the root endpoint info
  tryCatch({
    req <- httr2::request(base_url)
    # Add Accept header to ensure JSON response
    req <- httr2::req_headers(req, Accept = "application/json")
    req <- .add_headers(req, headers)
    res <- httr2::req_perform(req)
    httr2::resp_check_status(res)
    body <- httr2::resp_body_json(res, simplifyVector = FALSE)

    # Show auth status with gum styling
    message("CramerDB Authentication Status")

    if (!is.null(body[["authenticated"]])) {
      is_authed <- isTRUE(body[["authenticated"]])

      # Display authentication status
      if (is_authed) {
        message("Authenticated : YES")

        if (!is.null(body[["user"]])) {
          message("User : ", body[["user"]])
        }
      } else {
        message("Authenticated : NO")
        warning("Not authenticated\n",
                "  To authenticate, use: set_token('your_token_here')")
      }
    } else {
      stop("Unable to determine authentication status")
    }

    invisible(body)

  }, error = function(e) {
    message("Error checking authentication")
    message("  ", conditionMessage(e))
    invisible(NULL)
  })
}

# Internal helper to build endpoint URL from base + path
.build_endpoint_url <- function(base_url, path = NULL) {
  # Ensure base_url ends with /
  if (!grepl("/$", base_url)) {
    base_url <- paste0(base_url, "/")
  }

  # If no path provided, return base
  if (is.null(path) || !nzchar(path)) {
    return(base_url)
  }

  # Remove leading/trailing slashes from path
  path <- gsub("^/+|/+$", "", path)

  # Ensure path ends with /
  if (!grepl("/$", path)) {
    path <- paste0(path, "/")
  }

  paste0(base_url, path)
}

#' @title List field names at an API endpoint
#' @description
#' Returns a character vector of field names available at the given endpoint.
#' First attempts an OPTIONS request to read the DRF schema; falls back to
#' fetching one record and reading its keys.
#'
#' @param path Character. Endpoint path (e.g., "seine/event/").
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @param headers Named list of HTTP headers.
#' @param staging Logical. If TRUE, routes to the staging server.
#' @return A character vector of field names (visible), or NULL on failure.
#' @export
fields <- function(path, base_url = "https://cramerdb.com/api/",
                   headers = list(), staging = FALSE) {
  base_url <- .resolve_base_url(base_url, staging)
  headers  <- .auth_headers(headers)
  url      <- .build_endpoint_url(base_url, path)

  field_names <- tryCatch({
    # Step 1: OPTIONS request — DRF returns schema in actions.POST / PUT / PATCH
    req <- httr2::request(url)
    req <- httr2::req_method(req, "OPTIONS")
    req <- httr2::req_headers(req, Accept = "application/json")
    req <- .add_headers(req, headers)
    res <- httr2::req_perform(req)

    field_info <- NULL
    if (httr2::resp_status(res) == 200) {
      body    <- httr2::resp_body_json(res, simplifyVector = FALSE)
      actions <- body[["actions"]]
      if (!is.null(actions)) {
        field_info <- actions[["POST"]] %||% actions[["PUT"]] %||%
                      actions[["PATCH"]] %||% actions[[1]]
      }
    }

    if (!is.null(field_info) && length(field_info) > 0) {
      message(sprintf("Fields at %s", url))
      for (nm in names(field_info)) {
        fi       <- field_info[[nm]]
        type     <- fi[["type"]] %||% "unknown"
        req_fld  <- if (isTRUE(fi[["required"]])) " (required)" else ""
        styled_nm   <- sprintf("  %-25s", nm)
        styled_type <- paste0(type, req_fld)
        message(styled_nm, " ", styled_type)
      }
      return(names(field_info))
    }

    # Step 2: Fallback — fetch one record
    req2 <- httr2::request(url)
    req2 <- httr2::req_headers(req2, Accept = "application/json")
    req2 <- .add_headers(req2, headers)
    req2 <- httr2::req_url_query(req2, page_size = 1, labels = "1")
    res2 <- httr2::req_perform(req2)
    httr2::resp_check_status(res2)
    body2   <- httr2::resp_body_json(res2, simplifyVector = FALSE)
    results <- body2[["results"]]
    if (!is.null(results) && length(results) > 0) {
      nms <- names(results[[1]])
      message(sprintf("Fields at %s", url))
      for (nm in nms) {
        message(sprintf("  %s", nm))
      }
      return(nms)
    }

    warning(sprintf("No fields found at %s", url))
    invisible(NULL)

  }, error = function(e) {
    message(sprintf("Error fetching fields from %s", url))
    message("  ", conditionMessage(e))
    invisible(NULL)
  })

  field_names
}

# filters() — commented out pending proper Django-side filter metadata support
#
# #' @title List available query filters for an API endpoint
# #' @export
# filters <- function(path, base_url = "https://cramerdb.com/api/",
#                     headers = list(), staging = FALSE) {
#   base_url <- .resolve_base_url(base_url, staging)
#   headers  <- .auth_headers(headers)
#   url      <- .build_endpoint_url(base_url, path)
#
#   tryCatch({
#     req <- httr2::request(url)
#     req <- httr2::req_method(req, "OPTIONS")
#     req <- httr2::req_headers(req, Accept = "application/json")
#     req <- .add_headers(req, headers)
#     res <- httr2::req_perform(req)
#
#     filter_info <- NULL
#     if (httr2::resp_status(res) == 200) {
#       body <- httr2::resp_body_json(res, simplifyVector = FALSE)
#       filter_info <- body[["filters"]] %||%
#                      body[["filter_fields"]] %||%
#                      body[["available_filters"]] %||%
#                      body[["query_params"]]
#     }
#
#     if (!is.null(filter_info) && length(filter_info) > 0) {
#       .gum_header(sprintf("Available filters at %s", url))
#       nms <- if (is.null(names(filter_info))) as.character(filter_info) else names(filter_info)
#       for (nm in nms) {
#         fi        <- if (is.list(filter_info)) filter_info[[nm]] else list()
#         type_lbl  <- fi[["type"]] %||% fi[["lookup_expr"]] %||% ""
#         styled_nm   <- .gum_style(sprintf("  %-28s", nm),
#                                    color = .gum_colors$primary, bold = TRUE)
#         styled_type <- .gum_style(type_lbl, color = .gum_colors$muted)
#         cat(styled_nm, styled_type, "\n", sep = "")
#       }
#       cat("\n")
#       return(invisible(nms))
#     }
#
#     # Fallback: no metadata — show usage guide
#     .gum_header(sprintf("Filters at %s", url))
#     .gum_warning("No filter metadata returned by this endpoint.")
#     cat("\n")
#     cat(.gum_style("  Apply filters via the query parameter in fetch():\n",
#                    color = .gum_colors$muted))
#     cat(.gum_style("    fetch(\"", color = .gum_colors$muted),
#         .gum_style(path,           color = .gum_colors$primary),
#         .gum_style("\", query = list(\n", color = .gum_colors$muted), sep = "")
#     cat(.gum_style("      field         = \"value\",\n", color = .gum_colors$muted))
#     cat(.gum_style("      field__in     = c(\"val1\", \"val2\"),  # vector -> CSV\n",
#                    color = .gum_colors$muted))
#     cat(.gum_style("      field__gte    = 2020\n", color = .gum_colors$muted))
#     cat(.gum_style("    ))\n\n", color = .gum_colors$muted))
#     cat(.gum_style(
#       "  Common Django lookup suffixes: __in  __exact  __gte  __lte  __icontains\n\n",
#       color = .gum_colors$muted))
#     invisible(NULL)
#
#   }, error = function(e) {
#     .gum_error(sprintf("Error fetching filter info from %s", url))
#     cat("  ", conditionMessage(e), "\n", sep = "")
#     invisible(NULL)
#   })
# }

# Reuse helpers from fetch.R
.add_headers <- function(req, headers) {
  if (length(headers) > 0) {
    req <- do.call(httr2::req_headers, c(list(req), headers))
  }
  req
}
