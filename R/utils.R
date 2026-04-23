`%||%` <- function(a, b) if (is.null(a)) b else a

.normalize_url <- function(url, base_url = "https://cramerdb.com/api/") {
  if (grepl("^https?://", url)) return(url)
  if (!grepl("/$", base_url)) base_url <- paste0(base_url, "/")
  paste0(base_url, gsub("^/+", "", url))
}

.resolve_base_url <- function(base_url, staging = FALSE) {
  if (isTRUE(staging) || isTRUE(getOption("cramerdb.staging")))
    "https://staging.cramerdb.com/api/"
  else
    base_url
}

.add_headers <- function(req, headers) {
  if (length(headers) > 0) req <- do.call(httr2::req_headers, c(list(req), headers))
  req
}

.is_verbose <- function() isTRUE(getOption("cramerdb_verbose", FALSE))

.join_url <- function(base, id) {
  base <- as.character(base)
  id   <- utils::URLencode(as.character(id), reserved = TRUE)
  if (grepl("/$", base)) paste0(base, id, "/") else paste0(base, "/", id, "/")
}
