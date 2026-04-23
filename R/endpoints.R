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
