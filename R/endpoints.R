#' List available API endpoints
#'
#' Navigate the CramerDB API by listing endpoints at a given path.
#' With no arguments, lists root-level endpoints.
#'
#' @param path Character. Relative path (e.g. `"seine"`, `"biology"`).
#'   If NULL, lists root endpoints.
#' @param base_url Character. Base API URL.
#' @param headers Named list of additional HTTP headers.
#' @param timeout Integer. Request timeout in seconds. Default 60.
#' @param max_tries Integer. Maximum retry attempts for transient errors (429, 503). Default 3.
#' @return Invisibly returns the parsed JSON response.
#' @export
endpoints <- function(path = NULL, base_url = "https://api.cramerdb.com/rest/",
                      headers = list(),
                      timeout = 60L, max_tries = 3L) {
  headers  <- .auth_headers(headers)
  url      <- if (is.null(path) || !nzchar(path)) base_url else .normalize_url(path, base_url)
  .check_url_trusted(url)

  body <- .fetch_once(url, headers, labels = FALSE, timeout = timeout, max_tries = max_tries)

  eps <- body[["endpoints"]]

  if (length(eps) == 0) {
    message("No endpoints at ", url)
    return(invisible(body))
  }

  nms <- sort(names(eps))
  message("Endpoints at ", url)
  for (nm in nms) message(sprintf("  %-20s  %s", .sanitize(nm), .sanitize(eps[[nm]])))
  invisible(body)
}

#' List fields available at an API endpoint
#'
#' Tries an OPTIONS request first to read the DRF schema; falls back to
#' fetching one record and inspecting its keys.
#'
#' @param path Character. Endpoint path (e.g. `"seine/event/"`).
#' @param base_url Character. Base API URL.
#' @param headers Named list of additional HTTP headers.
#' @param timeout Integer. Request timeout in seconds. Default 60.
#' @param max_tries Integer. Maximum retry attempts for transient errors (429, 503). Default 3.
#' @return A character vector of field names, or NULL on failure.
#' @export
fields <- function(path, base_url = "https://api.cramerdb.com/rest/",
                   headers = list(),
                   timeout = 60L, max_tries = 3L) {
  user_headers <- headers
  headers      <- .auth_headers(headers)
  url          <- .normalize_url(path, base_url)
  .check_url_trusted(url)

  nms <- tryCatch({
    req <- httr2::req_method(httr2::request(url), "OPTIONS")
    req <- httr2::req_timeout(req, timeout)
    req <- httr2::req_options(req, followlocation = 0L)
    req <- httr2::req_headers(req, Accept = "application/json")
    req <- .add_headers(req, headers)
    req <- httr2::req_retry(req, max_tries = max_tries,
                            is_transient = \(r) httr2::resp_status(r) %in% c(429L, 503L))
    res <- httr2::req_perform(req)
    .check_no_redirect(res)
    httr2::resp_check_status(res)
    acts <- httr2::resp_body_json(res, simplifyVector = FALSE)[["actions"]]
    fi   <- acts[["POST"]] %||% acts[["PUT"]] %||% acts[["PATCH"]] %||% acts[[1]]
    if (length(fi)) names(fi)
  }, error = function(e) {
    # An endpoint that does not answer OPTIONS is normal; a rejected token is not.
    if (inherits(e, c("httr2_http_401", "httr2_http_403"))) stop(e)
    NULL
  })

  if (is.null(nms)) {
    df  <- fetch(url, headers = user_headers, query = list(page_size = 1),
                 timeout = timeout, max_tries = max_tries)
    nms <- if (nrow(df) > 0) names(df)
  }

  if (!is.null(nms)) {
    message("Fields at ", url)
    for (nm in nms) message("  ", .sanitize(nm))
  } else {
    message("No fields found at ", url)
  }
  nms
}
