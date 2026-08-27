# R/auth.R

#' Set the CramerDB API token for this R session (disabled)
#'
#' `set_token()` is disabled and always errors. Calling it with a token
#' value risks that value being written to `.Rhistory` in plain text.
#' That is how a token was previously leaked.
#'
#' Set your token with `options(cramerdb.token = ...)` in `~/.Rprofile`
#' instead, or with the `CRAMERDB_TOKEN` environment variable in
#' `~/.Renviron`. See the Authentication section of `README.md` for
#' details. The function is kept (rather than removed) so existing calls
#' fail with a clear message instead of "could not find function".
#'
#' @param token Unused; kept for backwards-compatible call signatures.
#' @export
set_token = function(token)
{
  stop(
    "set_token() is disabled: it can leave your token in plain text in .Rhistory.\n",
    "Set your token with options(cramerdb.token = '...') in ~/.Rprofile, or\n",
    "the CRAMERDB_TOKEN environment variable in ~/.Renviron.\n",
    "See the Authentication section of README.md for details.",
    call. = FALSE
  )
}

#' Get the currently configured CramerDB API token
#'
#' Retrieves the token from (in order of priority):
#' 1. R options (`getOption("cramerdb.token")`)
#' 2. `CRAMERDB_TOKEN` environment variable
#'
#' @param error_if_missing Logical. If TRUE, error when no token is found.
#' @return The token string, or NULL if not set (and `error_if_missing = FALSE`).
#' @examples
#' \dontrun{
#' get_token()
#' }
#' @export
get_token <- function(error_if_missing = FALSE) {
  token <- getOption("cramerdb.token", default = "")

  if (!nzchar(token)) {
    token <- Sys.getenv("CRAMERDB_TOKEN", "")
  }

  if (!nzchar(token)) {
    if (isTRUE(error_if_missing)) {
      stop(
        "No CramerDB API token found.\n",
        "Set options(cramerdb.token = '...') in ~/.Rprofile, or\n",
        "set the CRAMERDB_TOKEN environment variable in ~/.Renviron.",
        call. = FALSE
      )
    }
    return(NULL)
  }

  token
}

#' Clear stored CramerDB API token
#'
#' Removes the token from the current R session options.
#'
#' @return Invisibly returns TRUE
#' @export
#' @examples
#' \dontrun{
#' clear_token()
#' }
clear_token <- function() {
  options(cramerdb.token = NULL)
  message("Token cleared from current session")
  invisible(TRUE)
}

# Internal helper: merge stored token into headers (if no Authorization supplied)
.auth_headers <- function(headers = list()) {
  if ("Authorization" %in% names(headers)) {
    return(headers)
  }

  token <- get_token(error_if_missing = FALSE)
  if (is.null(token)) {
    return(headers)
  }

  c(headers, list(Authorization = paste("Token", token)))
}
