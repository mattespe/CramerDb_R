# Integration tests — requires a valid token and network access.
# Run interactively after devtools::load_all() or library(cramerdb).
#
# Usage:
#   Rscript tests/test_integration.R
#   # or from R: source("tests/test_integration.R")

library(cramerDBlite)

# set_token("your_token_here")   # uncomment if token not already stored

# --- auth ---------------------------------------------------------------------
tok <- get_token()
stopifnot(is.character(tok), nzchar(tok))
whoami()

# --- endpoints  ---------------------------------------------------------------
endpoints()
endpoints("core/")
message("Endpoints: OK")

# --- fields -------------------------------------------------------------------
flds <- fields("seine/event/")
stopifnot(is.character(flds), length(flds) > 0)
message("fields: OK (", length(flds), " fields)")

# --- fetch (single page) ------------------------------------------------------
df <- fetch("core/site/", query = list(page_size = 5))
stopifnot(is.data.frame(df), nrow(df) > 0)
message("fetch single page: OK (", nrow(df), " rows)")

# --- fetch (paginated) --------------------------------------------------------
df_all <- fetch("core/site/")
stopifnot(is.data.frame(df_all), nrow(df_all) >= nrow(df))
message("fetch paginated: OK (", nrow(df_all), " rows)")

# --- dry run (no writes) ------------------------------------------------------
test_row <- data.frame(field1 = "test_value", stringsAsFactors = FALSE)
create("core/site/", test_row, dry_run = TRUE)
message("create dry_run: OK")

message("All integration tests passed.")
