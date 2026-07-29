# Contributing to FAA Airports & Navaids

## Purpose

This repository provides a data pipeline for ingesting FAA aeronautical reference data
(airports and navaids) from the NASR 28-day subscription, storing it in Supabase PostgreSQL,
and exposing it via REST API.

## Setup

```bash
git clone https://github.com/mikehickey2/airports-navaids.git
cd airports-navaids
Rscript -e "renv::restore()"
```

## Common Commands

### Quality Gates

```bash
# Run all tests
Rscript -e "testthat::test_dir('tests/testthat')"

# Run a single test file
Rscript -e "testthat::test_file('tests/testthat/test-run_cleaning.R')"

# Lint R files and tests
Rscript -e "lintr::lint_dir('R')"
Rscript -e "lintr::lint_dir('tests')"

# Lint a single file
Rscript -e "lintr::lint('R/run_cleaning.R')"
```

### Package Management

```bash
# Restore packages from lockfile
Rscript -e "renv::restore()"

# Add a new package
Rscript -e "renv::install('package_name')"

# Snapshot current packages
Rscript -e "renv::snapshot(type = 'implicit')"
```

The type is set to `implicit` in `renv/settings.json`. Passing it explicitly keeps
the command honest if that setting ever changes. This previously read
`type = 'all'`, which contradicts the project setting and would snapshot every
package in the library, including ones that are not project dependencies.

### Run Pipeline

```r
# Full pipeline: check FAA, download, clean, push
source("R/scrape_airports_navaids.R")

# Push existing clean data to Supabase
source("R/push_to_supabase.R")
```

## Quality Gates

All enforced gates must pass before merge.

### Enforced Gates

| Gate | Tool | Fails When |
|------|------|------------|
| Line length | `.lintr` (lintr) | Any line exceeds 110 characters |
| Lint check | `lintr::lint_dir('R')` + `lintr::lint_dir('tests')` | lintr reports any issues |
| Test suite | `testthat::test_dir()` | Any testthat test fails |

### Policy Gates (Code Review)

| Gate | Expectation |
|------|-------------|
| Script size soft limit | Scripts should stay under 300 lines; refactor if exceeded |
| Function size limit | Functions should stay under 80 lines |
| Fail-loud conventions | No `suppressWarnings()`, `suppressMessages()`, or `tryCatch` without approval |
| Tidyverse style | Follow tidyverse conventions; use `styler` for formatting |

## CI Toolchain Maintenance

Both workflows pin the runner image and a dated Posit Package Manager snapshot.
That buys reproducible builds, and it creates five standing obligations. Each one
below was learned by breaking it; none is inferable from reading the workflow
files cold.

1. **When `renv.lock` changes, move the PPM snapshot date in both
   `.github/workflows/ci.yml` and `.github/workflows/daily-pipeline.yml`, in the
   same commit.** A package version that postdates the frozen snapshot does not
   exist in it and falls back to a slow source build from CRAN. A CI assertion
   fails the build if the two dates disagree.
2. **When Ubuntu 24.04 nears end of standard support (April 2029), bump the
   `runs-on` value and the PPM codename together.** They are a matched pair;
   changing one alone reintroduces the drift the pin was added to prevent.
3. **Review the pinned `r-lib/actions` commit SHAs periodically.** Pinned SHAs do
   not receive upstream security fixes automatically.
4. **`use-public-rspm: false` must stay on both `Setup R` steps.** Without it,
   `setup-r` writes `RENV_CONFIG_REPOS_OVERRIDE` into `GITHUB_ENV`, which shadows
   the workflow-level value for every later step and silently defeats the pinned
   snapshot. `ci.yml`'s two-repo assertion catches this on every run;
   `daily-pipeline.yml`'s post-`Setup R` assertion catches it on cycle day.
5. **The override must use the `NAME=URL` form.** `renv_repos_validate()`
   auto-names a single unnamed repository `CRAN`, but aborts with
   `all repository entries must be named` on two or more. An unnamed two-entry
   override fails `renv::restore()` outright, and `available.packages()`
   tolerating it proves nothing, because that is not the function which validates
   names.

The second repository in `RENV_CONFIG_REPOS_OVERRIDE` is a deliberate fallback.
The separator is a semicolon; renv does not split on commas. A package the
snapshot lacks resolves from CRAN as a source build, so the build degrades in time
rather than failing.

`lintr` is pinned outside `renv.lock` and is excluded from the "zero source
builds" expectation however it resolves.

## Assertions in CI

An assertion added to CI must be demonstrated to fail on the input it exists to
catch, and that demonstration is part of the change's evidence. An assertion that
has never been observed failing is an untested branch.

Two assertions in this repository passed on input the system rejects before they
were strengthened. A third exited with a bare status code and no diagnostic on its
failure path. A fourth, which read the file it was embedded in, matched its own
source text; standalone fixtures could not reproduce that, because they read a
different file. When an assertion's input includes the assertion, exercise it in
place, never on a copy.

## Branch and PR Workflow

### Branch Naming

Use descriptive prefixes:

```
feat/add-runway-data
fix/coordinate-parsing
docs/update-schema-docs
refactor/extract-api-helpers
test/add-push-coverage
data/update-faa-subscription
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>
```

**Types:** `feat`, `fix`, `data`, `docs`, `refactor`, `test`, `chore`

**Examples:**

```
feat(scrape): add retry logic for FAA downloads
fix(clean): correct state_code filtering
docs: update Supabase configuration section
refactor(push): extract batch upload to helper
test(clean): add edge cases for empty CSV
chore(renv): snapshot new package version
data: update to December 2025 FAA subscription
```

### Push and PR

1. Run all quality gates locally before pushing
2. Push branch and open a PR
3. Request review before merging (even for solo work)
4. Merge is blocked if any enforced gate fails

## Directory Structure

```
airports-navaids/
|-- R/
|   |-- scrape_airports_navaids.R  # Main orchestrator
|   |-- clean_airports.R           # Airport cleaning and validation
|   |-- clean_navaids.R            # Navaid cleaning and validation
|   |-- run_cleaning.R             # Cleaning-stage orchestration + dispatcher
|   |-- push_to_supabase.R         # Database upload
|-- sql/
|   |-- create_tables.sql          # PostgreSQL schema
|-- tests/testthat/                # testthat test files
|-- data/
|   |-- raw/                       # Downloaded FAA CSV files (dated dirs)
|   |-- clean/                     # Processed outputs (airports.csv, navaids.csv)
|-- .claude/                       # Claude Code agents and skills
```

**Do not create new top-level directories without approval.**

Approved directories: `R/`, `scripts/`, `tests/`, `sql/`, `data/`, `.claude/`, `renv/`

## Testing Conventions

Tests use **testthat edition 3** (declared in `helper-setup.R`).

### File Naming

Test files must match source files:
- `R/run_cleaning.R` -> `tests/testthat/test-run_cleaning.R`
- `R/push_to_supabase.R` -> `tests/testthat/test-push_to_supabase.R`

### Coverage Requirements

Each function needs tests for:
- Happy path (normal execution)
- Input validation (type errors, missing args)
- Edge cases (empty inputs, boundary values)
- Error conditions (correct error class)

### Patterns

**Temp file cleanup** - use `withr::local_tempdir()`:
```r
test_that("function works", {
  temp_dir <- withr::local_tempdir()  # Auto-cleaned when test ends
  # ...
})
```

**Error testing** - match on class, not message:
```r
expect_error(my_function(bad_input), class = "my_error_class")
```

**Environment variables** - use `withr::local_envvar()`:
```r
withr::local_envvar(SUPABASE_API_KEY = "test_key")
```

**HTTP mocking** - use httptest2:
```r
skip_if_not_installed("httptest2")
httptest2::without_internet({
  httptest2::expect_POST(push_to_supabase("airports", data), url = "...")
})
```

**Skip conditions** for external resources:
```r
skip_on_cran()
skip_if_offline()
skip_on_ci()
```

### Fixtures

Use helpers from `tests/testthat/helper-setup.R`:
- `sample_airports(n)` - generate test airport tibbles
- `sample_navaids(n)` - generate test navaid tibbles
- `create_test_raw_data_dir()` - temp dir with sample FAA CSVs
- `source_project_file("file.R")` - source from project root

## Raw Data Handling

Raw data files in `data/raw/` should not be modified after download.

The pipeline:
1. Downloads dated FAA subscription files to `data/raw/{date}_*_CSV/`
2. Cleans and filters data to `data/clean/`
3. Pushes clean data to Supabase (deletes then inserts)

Old raw data directories are deleted when new data is downloaded.

## Line Length Policy

- **Default target**: 80 characters per line for general R code
- **Allowed exceptions up to 110 characters** when wrapping reduces clarity:
  - File paths, regex patterns, URL strings
  - Long function calls that become harder to read when split
- **Hard stop at 120 characters**: refactor if exceeded
- Use `# nolint` only for rare cases with explanatory comment
