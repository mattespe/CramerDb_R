`%||%` <- function(a, b) if (is.null(a)) b else a

.normalize_url <- function(url, base_url = "https://api.cramerdb.com/rest/") {
  if (!endsWith(base_url, "/")) base_url <- paste0(base_url, "/")
  url <- sub("^/+", "", url)
  httr2::url_build(httr2::url_parse(url, base_url = base_url))
}

.allowed_hosts = function()
{
  defaults = c("api.cramerdb.com")
  extra = as.character(getOption("cramerdb.allowed_hosts", character(0)))
  unique(tolower(c(defaults, extra)))
}

# Gate every credentialed request: https only, host on the allowlist.
.check_url_trusted = function(url)
{
  parsed = httr2::url_parse(url)
  scheme = tolower(parsed$scheme %||% "")
  host = tolower(parsed$hostname %||% "")
  if (!identical(scheme, "https")) {
    stop(
      sprintf("Refusing to send credentials over '%s'; https is required.",
              if (nzchar(scheme)) scheme else "(no scheme)"),
      call. = FALSE
    )
  }
  if (!host %in% .allowed_hosts()) {
    stop(
      sprintf("Refusing to send credentials to untrusted host '%s'.\n", host),
      "See the Authentication section of README.md to configure allowed hosts.",
      call. = FALSE
    )
  }
  invisible(url)
}

# Redirects are not followed; the target would escape .check_url_trusted().
.check_no_redirect = function(res)
{
  status = httr2::resp_status(res)
  if (status >= 300L && status < 400L) {
    stop(
      sprintf("Server returned HTTP %d redirecting to '%s'. Redirects are not followed.\n",
              status, .sanitize(httr2::resp_header(res, "Location") %||% "(none)")),
      "If the path is missing a trailing slash, add one.",
      call. = FALSE
    )
  }
  invisible(res)
}

# Server text reaches the console; strip escapes that could rewrite the terminal.
.sanitize = function(x)
{
  gsub("[[:cntrl:]]", "", as.character(x))
}

.add_headers <- function(req, headers) {
  if (length(headers) > 0) req <- do.call(httr2::req_headers, c(list(req), headers))
  req
}

.join_url <- function(base, id) {
  base <- as.character(base)
  id   <- utils::URLencode(as.character(id), reserved = TRUE)
  if (grepl("/$", base)) paste0(base, id, "/") else paste0(base, "/", id, "/")
}
