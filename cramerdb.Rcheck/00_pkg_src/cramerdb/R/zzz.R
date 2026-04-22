# Package startup and cleanup hooks

.onAttach <- function(libname, pkgname) {
  packageStartupMessage("cramerdb: R interface for the CramerDB API")
  .check_for_updates()
}

.check_for_updates <- function() {
  try({
    current <- utils::packageVersion("cramerdb")
    req <- httr2::request(
      "https://raw.githubusercontent.com/ConnerSwineford/CramerDb_R/main/DESCRIPTION"
    )
    req <- httr2::req_timeout(req, 3)
    res <- httr2::req_perform(req)
    if (httr2::resp_status(res) == 200) {
      txt <- httr2::resp_body_string(res)
      m   <- regmatches(txt, regexpr("(?m)^Version:\\s*\\S+", txt, perl = TRUE))
      if (length(m) == 1) {
        latest <- package_version(trimws(sub("Version:\\s*", "", m)))
        if (latest > current) {
          packageStartupMessage(sprintf(
            "\nA new version of cramerdb is available: %s (installed: %s)",
            latest, current
          ))
          packageStartupMessage(
            "Update with: pak::pak(\"ConnerSwineford/CramerDb_R\")\n"
          )
        }
      }
    }
  }, silent = TRUE)
}
