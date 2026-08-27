# cramerDBlite

**cramerdb** is an R package for interacting with the CramerDB API. It provides simple functions to explore endpoints, fetch data into data frames or spatial objects (sf), and push data back to the database.

**cramerDBlite** is a modified version of the `cramerdb` package. The modifications focused on:

- minimal dependencies
- simplified code and decreased code complexity
- additional tests
- security improvements
- decreased verbosity

The `cramerDBlite` package is roughly 1/3 the amount of code while preserving essential functionality.

## Installation

```r

# Install cramerdb from GitHub
pak::pak("mattespe/CramerDb_R@lite")

# Load the package
library(cramerDBlite)
```

## Quick Start

```r
# 1. Set your authentication token (see Authentication section)

# 2. Explore available endpoints
endpoints()

endpoints("seine")

# 3. Fetch data
seine_events <- fetch("seine/event/")

seine_hauls <- fetch("seine/haul/")

# 5. Push data back
create("seine/event/", new_events)

update("seine/event/", updated_events)
upsert("seine/event/", new_or_updated_events)
```

---

## Authentication

### Set Your Token

Get your API token from the CramerDB web interface (https://cramerdb.com/admin/user/).

`set_token()` is disabled and stops with an error if you call it. It used to print the token to the console and record it in `.Rhistory`, which is often saved or shared accidentally.

Store the token outside your session history using one of these methods instead:

**Option 1 — R option in `~/.Rprofile`:**
```r
options(cramerdb.token = "your-api-token")
```

**Option 2 — Environment variable in `~/.Renviron`:**
```
CRAMERDB_TOKEN=your-api-token
```

Either file should be readable only by you:
```r
Sys.chmod("~/.Rprofile", mode = "0400")
```

Keep these files private — do not share or commit them.

### Connection Testing

Verify authentication:

```r
whoami()
```

### Retrieve Your Token

`get_token()` is disabled and stops with an error if you call it.
Returning the token lets it be printed to the console, which risks the
same `.Rhistory`/log leak as `set_token()`.

To confirm a token is configured and accepted, use `whoami()` (see
Connection Testing above). If you need the raw value, read it directly:

```r
getOption("cramerdb.token")
Sys.getenv("CRAMERDB_TOKEN")
```

---

## Exploring Endpoints

### List Available Endpoints

The `endpoints()` function helps you navigate the API structure:

```r
# List top-level endpoints
endpoints()
# Available endpoints at https://cramerdb.com/api/:
#   biology              https://cramerdb.com/api/biology/
#   core                 https://cramerdb.com/api/core/
#   habitatbreak         https://cramerdb.com/api/habitatbreak/
#   lab                  https://cramerdb.com/api/lab/
#   logger               https://cramerdb.com/api/logger/
#   permitting           https://cramerdb.com/api/permitting/
#   seine                https://cramerdb.com/api/seine/
#   snorkel              https://cramerdb.com/api/snorkel/
#   stranding            https://cramerdb.com/api/stranding/
#   tagging              https://cramerdb.com/api/tagging/
#   veg-rec              https://cramerdb.com/api/veg-rec/

# Drill down into specific sections
endpoints("seine")
# Available endpoints at https://cramerdb.com/api/seine/:
#   event                https://cramerdb.com/api/seine/event/
#   haul                 https://cramerdb.com/api/seine/haul/
#   net                  https://cramerdb.com/api/seine/net/
#   sample               https://cramerdb.com/api/seine/sample/

endpoints("biology")
endpoints("lab")
```

### Discover Fields

Use `fields()` to see what columns an endpoint returns:

```r
fields("seine/event/")
# Fields at https://cramerdb.com/api/seine/event/:
#   id                        string
#   project                   field (required)
#   survey                    field (required)
#   subsite                   field
#   event_date                date (required)
#   ...
```

---

## Fetching Data (Pull)

The `fetch()` function retrieves data from the API and converts it into R data frames or spatial objects.

### Basic Fetch

Use relative paths (automatically prepends `https://cramerdb.com/api/`):

```r
# Fetch seine events
events <- fetch("seine/event/")

# Fetch seine hauls
hauls <- fetch("seine/haul/")

# Fetch biology data
fish <- fetch("biology/fish/")

# Fetch lab samples
samples <- fetch("lab/sample/")
```

### Fetch with Full URLs

You can still use full URLs if needed:

```r
events <- fetch("https://cramerdb.com/api/seine/event/")
```

### Spatial Data (GeoJSON)

If the endpoint returns GeoJSON with point coordinates, `fetch()` automatically returns an `sf` spatial object:

```r
# Returns an sf tibble with geometry column
sites <- fetch("core/site/")

# Disable spatial conversion if you just want a regular data frame
sites_df <- fetch("core/site/", as_sf = FALSE)
```

### Pagination

The `fetch()` function automatically handles pagination, fetching all pages and combining them into a single data frame:

```r
# Fetches all pages automatically
all_events <- fetch("seine/event/")
```

---

## Pushing Data (Create/Update)

### Create New Records

Use `create()` to add new records via POST:

```r
# Create a data frame with new records
new_events <- data.frame(
  event_date = c("2025-01-15", "2025-01-16"),
  location = c("Site A", "Site B"),
  notes = c("Morning survey", "Evening survey")
)

# Push to the API
create("seine/event/", new_events)
```

### Update Existing Records

Use `update()` to modify existing records via PATCH. Requires an `id` column:

```r
# Fetch existing data
events <- fetch("seine/event/")

# Modify some records
events$notes[1] <- "Updated notes"

# Push updates back
update("seine/event/", events)
```

### Upsert (Create or Update)

Use `upsert()` to update records if they exist (based on `id`), or create them if they don't:

```r
# Mix of existing and new records
mixed_events <- data.frame(
  id = c(1, 2, NA, NA),  # IDs 1,2 exist; NA will create new
  event_date = c("2025-01-15", "2025-01-16", "2025-01-17", "2025-01-18"),
  notes = c("Updated", "Updated", "New", "New")
)

# Updates records 1 & 2, creates two new records
upsert("seine/event/", mixed_events)
```

### Spatial Data (GeoJSON)

For endpoints that accept GeoJSON, pass an `sf` object and it will automatically format as GeoJSON Features:

```r
library(sf)

# Create spatial data
sites <- st_as_sf(
  data.frame(
    name = c("Site A", "Site B"),
    lon = c(-121.5, -121.6),
    lat = c(38.5, 38.6)
  ),
  coords = c("lon", "lat"),
  crs = 4326
)

# Push spatial data
create("core/site/", sites)
```

---

## Advanced Features

### Dry-Run Mode

Preview what would be sent before actually sending it:

```r
# See what would be created without actually sending
create("seine/event/", new_events, dry_run = TRUE)

# Works with update() and upsert() too
update("seine/event/", events, dry_run = TRUE)
upsert("seine/event/", events, dry_run = TRUE)
```

### Verbose/Quiet Control

Control output verbosity for scripts vs interactive use:

```r
# Suppress all progress/styling (useful for scripts)
options(cramerdb.verbose = FALSE)
fetch("seine/event/")  # Silent operation

# Enable verbose output
options(cramerdb.verbose = TRUE)
fetch("seine/event/")  # Shows progress bars and messages

# Default: quiet 
```

---

## Advanced Options

### Custom Base URL

If you need to use a different API base URL:

```r
fetch("seine/event/", base_url = "https://staging.cramerdb.com/api/")
create("seine/event/", data, base_url = "https://staging.cramerdb.com/api/")
```

Note, URLs are checked against accepted Hosts (base URLs) to avoid accidently sending the API key to non-Cramer host. Additional hosts can be added via:

```r
options(cramerdb.allowed_hosts = "custom-url")
```

### Custom ID Column

By default, CRUD operations use the `id` column. To use a different column:

```r
update("seine/event/", events, id_col = "event_id")
upsert("seine/event/", events, id_col = "event_id")
```

### Manual Headers

Override the stored token with custom headers:

```r
custom_headers <- list(Authorization = "Token different_token_here")
fetch("seine/event/", headers = custom_headers)
create("seine/event/", data, headers = custom_headers)
```

### Chunk Size for Batch Operations

Control how many records are sent per batch (default: 200):

```r
# Send 50 records at a time
create("seine/event/", large_dataset, chunk_size = 50)
```

---

## Complete Workflow Example

```r
library(cramerdb)

# 1. Authenticate
whoami()

# 2. Explore the API
endpoints()
endpoints("seine")

# 3. Discover fields for an endpoint
fields("seine/event/")

# 4. Fetch existing data (optionally filtered)
seine_events <- fetch("seine/event/")
seine_events_hw <- fetch("seine/event/", query = list(project = "Hallwood"))
seine_hauls <- fetch("seine/haul/")

# 5. Analyze/modify data
seine_events <- seine_events |>
  filter(event_date > "2024-01-01") |>
  mutate(notes = paste(notes, "- Reviewed"))

# 6. Update records
update("seine/event/", seine_events)

# 7. Create new records
new_hauls <- data.frame(
  event_id = 123,
  haul_number = c(1, 2, 3),
  start_time = c("08:00", "10:00", "12:00")
)

create("seine/haul/", new_hauls)

# 8. Verify changes
updated_events <- fetch("seine/event/")
```

---

## Function Reference

### Core Functions

| Function | Description |
|----------|-------------|
| `fetch(url)` | Fetch data into a data frame/sf object |
| `create(url, data)` | Create new records (POST) |
| `update(url, data)` | Update existing records (PATCH) |
| `upsert(url, data)` | Create or update records |

### Authentication

| Function | Description |
|----------|-------------|
| `set_token(token)` | Disabled; errors with setup instructions |
| `get_token()` | Disabled; errors with setup instructions |
| `clear_token()` | Remove token from current session |
| `whoami()` | Check authentication status |

### Discovery & Navigation

| Function | Description |
|----------|-------------|
| `endpoints(path)` | List available API endpoints |
| `fields(path)` | List field names at an endpoint |


---

## Troubleshooting

### "Unexpected content type text/html"

This error occurs when not authenticated. Make sure to:
1. Set your token (see the Authentication section)
2. Verify authentication: `whoami()`

### "Failed to parse URL: Bad scheme"

Make sure to reload the package after installation:
```r
devtools::load_all()  # if developing
# or
library(cramerDBlite)  # after restarting R
```

### "HTTP 401 Unauthorized"

Your token may be invalid or expired. Get a new token from the CramerDB web interface (see the Authentication section for how to store it).

---

## LLM Policy

This project is developed with assistance from AI coding agents,
including Claude Code. Agent-assisted contributions are accepted subject
to the following. A change not meeting these requirements will not be
merged.

1. Style and idioms MUST match the project's existing code. This
   includes avoiding new dependency debt and favoring ease of
   maintenance over cleverness.
2. New functionality MUST be tested using the existing test suite's
   conventions.
3. New functionality or any change in behavior MUST be documented
   following the project's existing documentation style.
4. Changes MUST be intentional and motivated by a real defect or a
   required piece of functionality — not spontaneous refactors,
   speculative features, or unrequested abstractions. Where the project
   exposes a stable interface (e.g. an R package's exported functions),
   existing behavior MUST NOT break unless it can be demonstrated to be
   erroneous.
5. Every commit containing agent-assisted work MUST carry an
   `Assisted-by:` trailer naming the agent, model version, and any
   additional tooling used, e.g. `Assisted-by: Claude:Sonnet-5
   Claude-Code`. Basic development tools (git, gcc, make, editors)
   should not be listed.
6. All agent-assisted contributions MUST be reviewed and signed off by a
   human before inclusion. The human reviewer is ultimately responsible
   for any resulting errors or bugs.

Agents should read the project's `CLAUDE.md`, where present, since it is
curated to inform the points above with project-specific detail.
