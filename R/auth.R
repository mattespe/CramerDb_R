# R/auth.R

#' Set the CramerDB API token for this R session
#'
#' Stores the token in R options for the current session. In interactive
#' sessions you will be prompted to confirm, since the token will appear in
#' plain text in `.Rhistory`. For persistent storage across sessions, set the
#' option in your `~/.Rprofile` or use the `CRAMERDB_TOKEN` environment
#' variable in `~/.Renviron` instead.
#'
#' @param token Character scalar token value (no "Token " prefix needed).
#' @examples
#' \dontrun{
#' # Session-only (prompts for confirmation in interactive use)
#' set_token("abcd1234...")
#'
#' # Preferred: add to ~/.Rprofile for persistence without exposing in .Rhistory
#' # options(cramerdb.token = "abcd1234...")
#' }
#' @export
set_token <- function(token) {
  if (!is.character(token) || length(token) != 1L || !nzchar(token)) {
    stop("set_token(): `token` must be a non-empty character scalar.", call. = FALSE)
  }

  if (interactive()) {
    warning("Your token will be visible in this session and may be saved in .Rhistory.",
            "\nDelete .Rhistory and do not share it.",
            "\nPreferred alternative: set options(cramerdb.token = ...) in ~/.Rprofile",
            call. = FALSE, immediate. = TRUE)
    answer <- readline("Set token anyway? [y/N] ")
    if (!tolower(trimws(answer)) %in% c("y", "yes")) {
      message("Token not set.")
      return(invisible(NULL))
    }
  }

  options(cramerdb.token = token)
  invisible(token)
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
