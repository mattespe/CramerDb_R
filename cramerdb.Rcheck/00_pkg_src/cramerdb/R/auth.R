# R/auth.R

#' Set the CramerDB API token for this R session
#'
#' Stores the token securely in your system's credential store (Keychain on macOS,
#' Credential Manager on Windows, Secret Service on Linux). The token persists
#' across R sessions and is retrieved automatically when needed.
#'
#' If the keyring package is not available, falls back to storing in R options
#' for the current session only.
#'
#' @param token Character scalar token value (no "Token " prefix needed).
#' @param persist Logical. If TRUE (default), store in system keyring for persistence
#'   across sessions. If FALSE, store only in R options for current session.
#' @examples
#' \dontrun{
#' # Store token securely (persists across sessions)
#' set_token("abcd1234...")
#'
#' # Session-only storage
#' set_token("abcd1234...", persist = FALSE)
#' }
#' @export
set_token <- function(token, persist = TRUE) {
  if (!is.character(token) || length(token) != 1L || !nzchar(token)) {
    stop("set_token(): `token` must be a non-empty character scalar.", call. = FALSE)
  }

  # Always set in options for immediate use
  options(cramerdb.token = token)

  # Try to store in keyring if requested
  if (persist && .has_keyring()) {
    tryCatch({
      keyring::key_set_with_value(
        service = "cramerdb",
        username = "api_token",
        password = token
      )
      message("Token stored securely in system keyring")
      message("(Will auto-load in future R sessions)")
    }, error = function(e) {
      warning("Could not store token in keyring: ", conditionMessage(e), "\n",
              "Token saved for current session only.", call. = FALSE)
    })
  } else if (persist && !.has_keyring()) {
    message("Note: Install 'keyring' package for persistent token storage:")
    message("  install.packages('keyring')")
    message("Token saved for current session only.")
  }

  invisible(token)
}

#' Get the currently configured CramerDB API token
#'
#' Retrieves the token from (in order of priority):
#' 1. R options (current session)
#' 2. System keyring (if available)
#' 3. CRAMERDB_TOKEN environment variable
#'
#' @param error_if_missing Logical. If TRUE, error when no token is found.
#' @return The token string, or NULL if not set (and `error_if_missing = FALSE`).
#' @examples
#' \dontrun{
#' get_token()
#' }
#' @export
get_token <- function(error_if_missing = FALSE) {
  # 1. Check R options (current session)
  token <- getOption("cramerdb.token", default = "")

  # 2. Check keyring if not in options
  if (!nzchar(token) && .has_keyring()) {
    token <- .get_token_from_keyring()
  }

  # 3. Check environment variable
  if (!nzchar(token)) {
    token <- Sys.getenv("CRAMERDB_TOKEN", "")
  }

  if (!nzchar(token)) {
    if (isTRUE(error_if_missing)) {
      stop(
        "No CramerDB API token found.\n",
        "Use cramerdb::set_token('...') to store your token.",
        call. = FALSE
      )
    }
    return(NULL)
  }

  token
}

#' Clear stored CramerDB API token
#'
#' Removes the token from both the current R session and the system keyring.
#'
#' @return Invisibly returns TRUE
#' @export
#' @examples
#' \dontrun{
#' clear_token()
#' }
clear_token <- function() {
  # Clear from options
  options(cramerdb.token = NULL)

  # Clear from keyring if available
  if (.has_keyring()) {
    tryCatch({
      keyring::key_delete(service = "cramerdb", username = "api_token")
      message("Token removed from system keyring")
    }, error = function(e) {
      # Silently fail if key doesn't exist
      NULL
    })
  }

  message("Token cleared from current session")
  invisible(TRUE)
}

# Internal helper: merge stored token into headers (if no Authorization supplied)
.auth_headers <- function(headers = list()) {
  # If user already supplied an Authorization header, don't touch it
  if ("Authorization" %in% names(headers)) {
    return(headers)
  }

  token <- get_token(error_if_missing = FALSE)
  if (is.null(token)) {
    # No token configured; just return original headers
    return(headers)
  }

  c(headers, list(Authorization = paste("Token", token)))
}

# Check if keyring package is available
.has_keyring <- function() {
  requireNamespace("keyring", quietly = TRUE)
}

# Get token from keyring
.get_token_from_keyring <- function() {
  tryCatch({
    keyring::key_get(service = "cramerdb", username = "api_token")
  }, error = function(e) {
    # Return empty string if key doesn't exist
    ""
  })
}
