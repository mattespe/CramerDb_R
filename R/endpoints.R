#' List available API endpoints
#'
#' Navigate the CramerDB API by listing endpoints at a given path.
#' With no arguments, lists root-level endpoints.
#'
#' @param path Character. Relative path (e.g. `"seine"`, `"biology"`).
#'   If NULL, lists root endpoints.
#' @param base_url Character. Base API URL.
#' @param headers Named list of additional HTTP headers.
#' @param staging Logical. If TRUE, routes requests to the staging server.
#' @return Invisibly returns the parsed JSON response.
#' @export
endpoints <- function(path = NULL, base_url = "https://cramerdb.com/api/",
                      headers = list(), staging = FALSE) {
  headers  <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url      <- if (is.null(path) || !nzchar(path)) base_url else .normalize_url(path, base_url)
  .check_url_trusted(url)

  body <- .fetch_once(url, headers, labels = FALSE)

  eps <- body[["endpoints"]] %||% body[!names(body) %in% c("authenticated", "user")]

  if (length(eps) == 0) {
    message("No endpoints at ", url)
    return(invisible(body))
  }

  nms <- sort(names(eps))
  message("Endpoints at ", url)
  for (nm in nms) message(sprintf("  %-20s  %s", nm, eps[[nm]]))
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
#' @param staging Logical. If TRUE, routes requests to the staging server.
#' @return A character vector of field names, or NULL on failure.
#' @export
fields <- function(path, base_url = "https://cramerdb.com/api/",
                   headers = list(), staging = FALSE) {
  headers  <- .auth_headers(headers)
  base_url <- .resolve_base_url(base_url, staging)
  url      <- .normalize_url(path, base_url)
  .check_url_trusted(url)

  nms <- tryCatch({
    req <- httr2::req_method(httr2::request(url), "OPTIONS")
    req <- httr2::req_headers(req, Accept = "application/json")
    req <- .add_headers(req, headers)
    res <- httr2::req_perform(req)
    httr2::resp_check_status(res)
    acts <- httr2::resp_body_json(res, simplifyVector = FALSE)[["actions"]]
    fi   <- acts[["POST"]] %||% acts[["PUT"]] %||% acts[["PATCH"]] %||% acts[[1]]
    if (length(fi)) names(fi)
  }, error = function(e) NULL)

  if (is.null(nms)) {
    df  <- fetch(url, headers = headers, query = list(page_size = 1))
    nms <- if (nrow(df) > 0) names(df)
  }

  if (!is.null(nms)) {
    message("Fields at ", url)
    for (nm in nms) message("  ", nm)
  } else {
    message("No fields found at ", url)
  }
  nms
}
