pkgname <- "cramerdb"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
library('cramerdb')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("browse_endpoints")
### * browse_endpoints

flush(stderr()); flush(stdout())

### Name: browse_endpoints
### Title: Browse API endpoints interactively
### Aliases: browse_endpoints

### ** Examples

## Not run: 
##D # Interactive browsing (requires gum)
##D browse_endpoints()
##D 
##D # Start from a specific path
##D browse_endpoints(path = "seine")
## End(Not run)



cleanEx()
nameEx("clear_token")
### * clear_token

flush(stderr()); flush(stdout())

### Name: clear_token
### Title: Clear stored CramerDB API token
### Aliases: clear_token

### ** Examples

## Not run: 
##D clear_token()
## End(Not run)



cleanEx()
nameEx("endpoints")
### * endpoints

flush(stderr()); flush(stdout())

### Name: endpoints
### Title: List available API endpoints
### Aliases: endpoints

### ** Examples

## Not run: 
##D # List top-level endpoints
##D endpoints()
##D 
##D # List endpoints for a specific section
##D endpoints("seine")
##D endpoints("biology")
##D 
##D # Equivalent to:
##D endpoints("biology/some-sub-path")
## End(Not run)



cleanEx()
nameEx("get_token")
### * get_token

flush(stderr()); flush(stdout())

### Name: get_token
### Title: Get the currently configured CramerDB API token
### Aliases: get_token

### ** Examples

## Not run: 
##D get_token()
## End(Not run)



cleanEx()
nameEx("set_token")
### * set_token

flush(stderr()); flush(stdout())

### Name: set_token
### Title: Set the CramerDB API token for this R session
### Aliases: set_token

### ** Examples

## Not run: 
##D # Store token securely (persists across sessions)
##D set_token("abcd1234...")
##D 
##D # Session-only storage
##D set_token("abcd1234...", persist = FALSE)
## End(Not run)



cleanEx()
nameEx("test_connection")
### * test_connection

flush(stderr()); flush(stdout())

### Name: test_connection
### Title: Test connection to CramerDB API
### Aliases: test_connection

### ** Examples

## Not run: 
##D test_connection()
## End(Not run)



cleanEx()
nameEx("whoami")
### * whoami

flush(stderr()); flush(stdout())

### Name: whoami
### Title: Check authentication status
### Aliases: whoami

### ** Examples

## Not run: 
##D # Check authentication status
##D whoami()
##D 
##D # After setting token
##D set_token("your_token_here")
##D whoami()
## End(Not run)



### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
