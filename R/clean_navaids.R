# clean_navaids.R
# Functions for cleaning FAA navaid data (NAV_BASE.csv)
#
# Companion to run_cleaning.R, which holds the cleaning orchestration
# (run_cleaning(), the validate_cleaned_data() dispatcher, and the shared
# raw-directory helpers). clean_navaids() requires parquet_schema.R
# (schema_col_classes()) to be sourced; navaids validation through the
# dispatcher requires sourcing run_cleaning.R too.
#
# Usage:
#   source("R/parquet_schema.R")
#   source("R/clean_navaids.R")
#   navaids <- clean_navaids("data/raw/19_DEC_2024_NAV_CSV/NAV_BASE.csv")

library(checkmate)
library(rlang)

# --- Schema Definitions ---
#
# Navaids validation rules:
#   - Row count: warn if < 1000
#   - NAV_TYPE: warn if not in valid_nav_types
#
navaids_columns <- c(
  "EFF_DATE", "NAV_ID", "NAV_TYPE", "STATE_CODE", "CITY",
  "COUNTRY_CODE", "NAME", "STATE_NAME", "REGION_CODE",
  "LAT_HEMIS", "LAT_DEG", "LAT_MIN", "LAT_SEC", "LAT_DECIMAL",
  "LONG_HEMIS", "LONG_DEG", "LONG_MIN", "LONG_SEC", "LONG_DECIMAL",
  "ELEV", "MAG_VARN", "MAG_VARN_HEMIS", "MAG_VARN_YEAR", "ALT_CODE"
)

# See airports_parquet_schema in clean_airports.R for the rationale.
navaids_parquet_schema <- c(
  EFF_DATE = "DATE", NAV_ID = "STRING", NAV_TYPE = "STRING",
  STATE_CODE = "STRING", CITY = "STRING", COUNTRY_CODE = "STRING",
  NAME = "STRING", STATE_NAME = "STRING", REGION_CODE = "STRING",
  LAT_HEMIS = "STRING", LAT_DEG = "INT32", LAT_MIN = "INT32",
  LAT_SEC = "DOUBLE", LAT_DECIMAL = "DOUBLE", LONG_HEMIS = "STRING",
  LONG_DEG = "INT32", LONG_MIN = "INT32", LONG_SEC = "DOUBLE",
  LONG_DECIMAL = "DOUBLE", ELEV = "DOUBLE", MAG_VARN = "DOUBLE",
  MAG_VARN_HEMIS = "STRING", MAG_VARN_YEAR = "INT32", ALT_CODE = "STRING"
)

# Valid NAV_TYPE values per FAA NAV DATA LAYOUT documentation
valid_nav_types <- c(
  "CONSOLAN", "DME", "FAN MARKER", "MARINE NDB", "MARINE NDB/DME",
  "NDB", "NDB/DME", "TACAN", "UHF/NDB", "VOR", "VOR/DME", "VORTAC", "VOT"
)

#' Clean navaid data from FAA NAV_BASE.csv
#'
#' Reads NAV_BASE.csv and selects relevant columns.
#'
#' @param nav_base_path Path to NAV_BASE.csv file
#' @return Data frame with cleaned navaid data
#' @export
clean_navaids <- function(nav_base_path) {
  # --- Input validation ---
  checkmate::assert_file_exists(nav_base_path, extension = "csv")

  message("Reading navaids from: ", nav_base_path)

  # Verify required columns exist before the full read: every pinned
  # colClasses name is a required column, so read.csv() cannot warn about a
  # colClasses name missing from the file once this check passes. Reads only
  # the first data row (nrows = 0 is ignored and would read the whole file).
  # FAA files use ISO-8859-1 (Latin-1) encoding for special characters.
  header <- names(read.csv(
    nav_base_path,
    nrows = 1,
    fileEncoding = "ISO-8859-1",
    check.names = FALSE
  ))
  missing_cols <- setdiff(navaids_columns, header)
  if (length(missing_cols) > 0) {
    rlang::abort(
      c(
        "NAV_BASE.csv missing required columns",
        x = paste("Missing:", paste(missing_cols, collapse = ", "))
      ),
      class = "clean_data_schema_error"
    )
  }

  # STRING-declared columns are pinned as character so an all-digit NAV_ID
  # cannot be inferred as numeric (issue #41)
  navaids_raw <- read.csv(
    nav_base_path,
    fileEncoding = "ISO-8859-1",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    colClasses = schema_col_classes(navaids_parquet_schema)
  )

  navaids <- navaids_raw[, navaids_columns]

  # Validate result is not empty
  if (nrow(navaids) == 0) {
    rlang::abort(
      "No navaids found in NAV_BASE.csv",
      class = "clean_data_empty_result"
    )
  }

  message("Cleaned ", nrow(navaids), " navaids")
  navaids
}

#' Validate cleaned navaids data
#'
#' All navaids checks are non-halting warnings.
#'
#' @param data Data frame of cleaned navaids data
#' @return The input data (invisibly)
#' @keywords internal
validate_navaids <- function(data) {
  # Check expected row count (warning only)
  if (nrow(data) < 1000) {
    rlang::warn(
      paste("Expected at least 1000 navaids, got", nrow(data)),
      class = "validation_warning"
    )
  }

  # Check NAV_TYPE values (warning only)
  invalid_types <- setdiff(unique(data$NAV_TYPE), valid_nav_types)
  if (length(invalid_types) > 0) {
    rlang::warn(
      c(
        "Unexpected NAV_TYPE values found",
        i = paste("Unknown types:", paste(invalid_types, collapse = ", "))
      ),
      class = "validation_warning"
    )
  }

  invisible(data)
}
