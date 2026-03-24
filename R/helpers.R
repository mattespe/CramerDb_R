# Helper Functions for Enhanced Functionality

#' Test connection to CramerDB API
#'
#' Verifies that the API is reachable and your authentication is working.
#' Provides a quick health check before running data operations.
#'
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @return Invisibly returns TRUE if connection successful, FALSE otherwise
#' @export
#' @examples
#' \dontrun{
#' test_connection()
#' }
test_connection <- function(base_url = "https://cramerdb.com/api/", staging = FALSE) {
  base_url <- .resolve_base_url(base_url, staging)
  message("Testing CramerDB Connection")

  # Check internet connectivity first
  tryCatch({
    req <- httr2::request(base_url)
    req <- httr2::req_timeout(req, 5)  # 5 second timeout
    req <- httr2::req_headers(req, Accept = "application/json")

    cat("  Checking network connectivity...", "\r")
    flush.console()

    res <- httr2::req_perform(req)

    cat("  Checking network connectivity... ")
    message("OK")

  }, error = function(e) {
    message("Cannot reach API server")
    message("  ", conditionMessage(e), "\n", sep = "")
    return(invisible(FALSE))
  })

  # Check authentication
  token <- get_token(error_if_missing = FALSE)

  if (is.null(token)) {
    warning("No API token configured\n  Run: set_token('your_token_here')\n")
    return(invisible(FALSE))
  }

  message("  Verifying authentication...", "\r")
  flush.console()

  tryCatch({
    headers <- list(Authorization = paste("Token", token))
    req <- httr2::request(base_url)
    req <- httr2::req_headers(req, Accept = "application/json")
    req <- .add_headers(req, headers)
    res <- httr2::req_perform(req)
    body <- httr2::resp_body_json(res, simplifyVector = FALSE)

    message("  Verifying authentication...     ")

    if (isTRUE(body[["authenticated"]])) {
      message("Authenticated")
      if (!is.null(body[["user"]])) {
        message("  User: ", body[["user"]])
      }
      cat("\n")
      message("Connection test passed!")
      return(invisible(TRUE))
    } else {
      stop("Authentication failed\n  Token may be invalid or expired\n")
    }

  }, error = function(e) {
    message("Authentication check failed")
    cat("  ", conditionMessage(e), "\n", sep = "")
    return(invisible(FALSE))
  })
}

#' Browse API endpoints interactively
#'
#' Uses interactive filtering (if gum is available) to browse and explore
#' API endpoints. Falls back to listing all endpoints if gum is not available.
#'
#' @param base_url Character. Base API URL (default: "https://cramerdb.com/api/")
#' @param path Character. Optional starting path (e.g., "seine")
#' @return Selected endpoint URL or NULL if cancelled
#' @export
#' @examples
#' \dontrun{
#' # Interactive browsing (requires gum)
#' browse_endpoints()
#'
#' # Start from a specific path
#' browse_endpoints(path = "seine")
#' }
browse_endpoints <- function(base_url = "https://cramerdb.com/api/", path = NULL, staging = FALSE) {
  base_url <- .resolve_base_url(base_url, staging)

  headers <- .auth_headers(list())
  url <- .build_endpoint_url(base_url, path)

  # Fetch endpoints
  tryCatch({
    req <- httr2::request(url)
    req <- httr2::req_headers(req, Accept = "application/json")
    req <- .add_headers(req, headers)
    res <- httr2::req_perform(req)
    httr2::resp_check_status(res)
    body <- httr2::resp_body_json(res, simplifyVector = FALSE)

    # Get endpoint list
    ep_list <- if (!is.null(body[["endpoints"]])) {
      body[["endpoints"]]
    } else {
      body[!names(body) %in% c("authenticated", "user")]
    }

    if (length(ep_list) == 0) {
      message("No endpoints found at ", url)
      return(invisible(NULL))
    }

    # Prepare options for interactive selection
    ep_names <- names(ep_list)
    ep_names <- ep_names[order(ep_names)]

    # Use gum filter for selection
    message("Browse endpoints at: ", url, "\n\n")

    selected <- .gum_filter(ep_names, prompt = "Search endpoints:")

    if (is.null(selected) || length(selected) == 0) {
      message("No selection made")
      return(invisible(NULL))
    }

    selected_url <- ep_list[[selected]]

    message("Selected:", selected)
    message("  URL: ", selected_url)

    return(invisible(selected_url))

  }, error = function(e) {
    message(sprintf("Error browsing %s", url))
    message("  ", conditionMessage(e), "\n", sep = "")
    return(invisible(NULL))
  })
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

# Output message only if verbose
.verbose_cat <- function(...) {
  if (.is_verbose()) {
    cat(...)
  }
}

# Add headers helper (if not already defined)
.add_headers <- function(req, headers) {
  if (length(headers) > 0) {
    req <- do.call(httr2::req_headers, c(list(req), headers))
  }
  req
}

# Build endpoint URL helper (if not already defined)
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
