`%||%` <- function(a, b) if (is.null(a)) b else a

.normalize_url <- function(url, base_url = "https://cramerdb.com/api/") {
  if (!endsWith(base_url, "/")) base_url <- paste0(base_url, "/")
  url <- sub("^/+", "", url)
  httr2::url_build(httr2::url_parse(url, base_url = base_url))
}

.resolve_base_url <- function(base_url, staging = FALSE) {
  if (isTRUE(staging) || isTRUE(getOption("cramerdb.staging")))
    "https://staging.cramerdb.com/api/"
  else
    base_url
}

.allowed_hosts <- function() {
  defaults <- c("cramerdb.com", "staging.cramerdb.com")
  extra <- getOption("cramerdb.allowed_hosts", character(0))
  unique(c(defaults, extra))
}

.check_url_trusted <- function(url) {
  host <- httr2::url_parse(url)$hostname
  allowed <- .allowed_hosts()
  if (!host %in% allowed) {
    stop(
      sprintf("Refusing to send credentials to untrusted host '%s'.\n", host),
      sprintf("Add it with: options(cramerdb.allowed_hosts = c('%s'))", host),
      call. = FALSE
    )
  }
  invisible(url)
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
