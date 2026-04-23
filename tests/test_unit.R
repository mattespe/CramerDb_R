library(cramerdb)

# --- .normalize_url -----------------------------------------------------------
stopifnot(
  cramerdb:::.normalize_url("seine/event/", "https://cramerdb.com/api/") ==
    "https://cramerdb.com/api/seine/event/",
  cramerdb:::.normalize_url("https://other.com/api/", "https://cramerdb.com/api/") ==
    "https://other.com/api/"
)

# --- .nulls_to_na -------------------------------------------------------------
x <- list(a = 1, b = NULL, c = list())
r <- cramerdb:::.nulls_to_na(x)
stopifnot(is.na(r$b), is.na(r$c))

# --- .bind_rows ---------------------------------------------------------------
df1 <- data.frame(a = 1L, b = "x", stringsAsFactors = FALSE)
df2 <- data.frame(a = 2L, stringsAsFactors = FALSE)
r <- cramerdb:::.bind_rows(list(df1, df2))
stopifnot(nrow(r) == 2, ncol(r) == 2, is.na(r$b[2]))

# --- .chunk_indices -----------------------------------------------------------
chunks <- cramerdb:::.chunk_indices(5, 2)
stopifnot(length(chunks) == 3, identical(chunks[[3]], 5L))

# --- .join_url ----------------------------------------------------------------
stopifnot(
  cramerdb:::.join_url("https://cramerdb.com/api/seine/event/", 42) ==
    "https://cramerdb.com/api/seine/event/42/"
)

# --- .features_to_tbl ---------------------------------------------------------
feats <- list(
  list(type = "Feature", id = "1", geometry = NULL,
       properties = list(name = "Site A", value = 10)),
  list(type = "Feature", id = "2", geometry = NULL,
       properties = list(name = "Site B", value = NULL))
)
df <- cramerdb:::.features_to_tbl(feats)
stopifnot(is.data.frame(df), nrow(df) == 2, names(df)[1] == "id", is.na(df$value[2]))

# --- .as_row_list -------------------------------------------------------------
df <- data.frame(id = c(1L, NA_integer_), name = c("a", "b"), stringsAsFactors = FALSE)
rows <- cramerdb:::.as_row_list(df, "id")
stopifnot(length(rows) == 2, is.null(rows[[2]]$id))

message("All unit tests passed.")
