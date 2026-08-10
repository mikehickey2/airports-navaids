# clean_airports.R
# Functions for cleaning FAA airport data (APT_BASE.csv)
#
# Companion to clean_navaids.R (navaids domain) and run_cleaning.R, which
# holds the cleaning orchestration and the validate_cleaned_data() dispatcher
# that delegates airports validation to validate_airports() defined here.
# clean_airports() requires parquet_schema.R (schema_col_classes()) to be
# sourced; airports validation through the dispatcher requires sourcing
# run_cleaning.R too.
#
# Usage:
#   source("R/clean_airports.R")
#   airports <- clean_airports("data/raw/19_DEC_2024_APT_CSV/APT_BASE.csv")

library(checkmate)
library(rlang)

# --- Schema Definitions ---
#
# Airports: ALL NASR landing facilities are admitted (no row filtering).
# Site type is carried via SITE_TYPE_CODE; facility use via facility_use.
#   - FACILITY_USE_CODE (PU/PR) is read as the mapping source for facility_use
#     and is NOT retained in the output.
#   - Row count: warn if < 18000
#   - LAT_DECIMAL / LONG_DECIMAL out-of-US-bounds: warn only, never filter
#
# Raw FAA source columns required to exist in APT_BASE.csv:
airports_source_columns <- c(
  "EFF_DATE", "SITE_NO", "SITE_TYPE_CODE", "STATE_CODE", "ARPT_ID",
  "CITY", "COUNTRY_CODE", "STATE_NAME", "COUNTY_NAME", "ARPT_NAME",
  "LAT_DEG", "LAT_MIN", "LAT_SEC", "LAT_HEMIS", "LAT_DECIMAL",
  "LONG_DEG", "LONG_MIN", "LONG_SEC", "LONG_HEMIS", "LONG_DECIMAL",
  "ELEV", "ELEV_METHOD_CODE", "MAG_VARN", "MAG_HEMIS", "MAG_VARN_YEAR",
  "ICAO_ID", "FACILITY_USE_CODE"
)

# Output columns: raw FACILITY_USE_CODE is dropped, derived facility_use added.
airports_columns <- c(
  "EFF_DATE", "SITE_NO", "SITE_TYPE_CODE", "STATE_CODE", "ARPT_ID",
  "CITY", "COUNTRY_CODE", "STATE_NAME", "COUNTY_NAME", "ARPT_NAME",
  "LAT_DEG", "LAT_MIN", "LAT_SEC", "LAT_HEMIS", "LAT_DECIMAL",
  "LONG_DEG", "LONG_MIN", "LONG_SEC", "LONG_HEMIS", "LONG_DECIMAL",
  "ELEV", "ELEV_METHOD_CODE", "MAG_VARN", "MAG_HEMIS", "MAG_VARN_YEAR",
  "ICAO_ID", "facility_use"
)

# Parquet type declarations, derived from sql/create_tables.sql so the Parquet
# file, the Postgres table, and the CSV agree. Names and order match
# airports_columns. Types are pinned rather than inferred: read.csv() guesses
# per-cycle, and a guess that changes between NASR cycles would silently break
# downstream consumers reading several cycles as one dataset.
airports_parquet_schema <- c(
  EFF_DATE = "DATE", SITE_NO = "STRING", SITE_TYPE_CODE = "STRING",
  STATE_CODE = "STRING", ARPT_ID = "STRING", CITY = "STRING",
  COUNTRY_CODE = "STRING", STATE_NAME = "STRING", COUNTY_NAME = "STRING",
  ARPT_NAME = "STRING", LAT_DEG = "INT32", LAT_MIN = "INT32",
  LAT_SEC = "DOUBLE", LAT_HEMIS = "STRING", LAT_DECIMAL = "DOUBLE",
  LONG_DEG = "INT32", LONG_MIN = "INT32", LONG_SEC = "DOUBLE",
  LONG_HEMIS = "STRING", LONG_DECIMAL = "DOUBLE", ELEV = "DOUBLE",
  ELEV_METHOD_CODE = "STRING", MAG_VARN = "DOUBLE", MAG_HEMIS = "STRING",
  MAG_VARN_YEAR = "INT32", ICAO_ID = "STRING", facility_use = "STRING"
)

#' Map FAA FACILITY_USE_CODE to a friendly label
#'
#' @param codes Character vector of FAA facility-use codes (PU/PR)
#' @return Character vector of "public"/"private"; aborts on any other value
#' @keywords internal
map_facility_use <- function(codes) {
  mapping <- c(PU = "public", PR = "private")
  unknown <- setdiff(unique(codes), names(mapping))
  if (length(unknown) > 0) {
    rlang::abort(
      c(
        "Unexpected FACILITY_USE_CODE value(s)",
        x = paste("Unknown:", paste(unknown, collapse = ", ")),
        i = "Expected only PU or PR"
      ),
      class = "clean_data_facility_use_error"
    )
  }
  unname(mapping[codes])
}

#' Clean airport data from FAA APT_BASE.csv
#'
#' Reads APT_BASE.csv, admits all NASR landing facilities (no row filtering),
#' maps FACILITY_USE_CODE to facility_use, and selects relevant columns.
#'
#' @param apt_base_path Path to APT_BASE.csv file
#' @return Data frame with cleaned airport data
#' @export
clean_airports <- function(apt_base_path) {
  # --- Input validation ---
  checkmate::assert_file_exists(apt_base_path, extension = "csv")

  message("Reading airports from: ", apt_base_path)

  # Verify required source columns exist before the full read: every pinned
  # colClasses name is a required column, so read.csv() cannot warn about a
  # colClasses name missing from the file once this check passes.
  # FAA files use ISO-8859-1 (Latin-1) encoding for special characters.
  header <- names(read.csv(
    apt_base_path,
    nrows = 0,
    fileEncoding = "ISO-8859-1",
    check.names = FALSE
  ))
  missing_cols <- setdiff(airports_source_columns, header)
  if (length(missing_cols) > 0) {
    rlang::abort(
      c(
        "APT_BASE.csv missing required columns",
        x = paste("Missing:", paste(missing_cols, collapse = ", "))
      ),
      class = "clean_data_schema_error"
    )
  }

  # Pin STRING-declared columns as character so read.csv() cannot infer an
  # all-digit SITE_NO as numeric and destroy leading zeros (issue #41).
  # facility_use is derived (absent from the raw file); FACILITY_USE_CODE is
  # raw-only.
  col_classes <- c(
    schema_col_classes(
      airports_parquet_schema[names(airports_parquet_schema) != "facility_use"]
    ),
    FACILITY_USE_CODE = "character"
  )

  airports_raw <- read.csv(
    apt_base_path,
    fileEncoding = "ISO-8859-1",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    colClasses = col_classes
  )

  # Map facility-use code to friendly label (fail loud on unknown code)
  airports_raw$facility_use <- map_facility_use(airports_raw$FACILITY_USE_CODE)

  # No row filtering: admit all site types and all ID lengths
  airports <- airports_raw[, airports_columns]

  if (nrow(airports) == 0) {
    rlang::abort(
      "No airports found in APT_BASE.csv",
      class = "clean_data_empty_result"
    )
  }

  message("Cleaned ", nrow(airports), " airports")
  airports
}

#' Validate cleaned airports data
#'
#' Fail-fast ordering: structural aborts first, then non-halting warnings.
#'
#' @param data Data frame of cleaned airports data
#' @return The input data (invisibly) if valid, otherwise aborts
#' @keywords internal
validate_airports <- function(data) {
  # facility_use column must be present (fail loud; NULL would pass vacuously)
  if (!"facility_use" %in% names(data)) {
    rlang::abort(
      "Column 'facility_use' is missing from airports data",
      class = "validation_error"
    )
  }

  # SITE_NO must be character: numeric inference destroys leading zeros and
  # collides distinct FAA site numbers (error - critical)
  if (!is.character(data$SITE_NO)) {
    rlang::abort(
      c(
        paste("SITE_NO must be character, got", class(data$SITE_NO)[[1]]),
        i = "clean_airports() pins SITE_NO via colClasses; check the read path"
      ),
      class = "validation_error"
    )
  }

  # facility_use must be one of the mapped labels (error - critical)
  if (!all(data$facility_use %in% c("public", "private"))) {
    rlang::abort(
      "facility_use contains values outside {public, private}",
      class = "validation_error"
    )
  }

  # Check expected row count (warning only)
  if (nrow(data) < 18000) {
    rlang::warn(
      paste("Expected at least 18000 airports, got", nrow(data)),
      class = "validation_warning"
    )
  }

  # Check latitude range (warning only - never filter; US territories)
  lat_valid <- data$LAT_DECIMAL >= 18 & data$LAT_DECIMAL <= 72
  if (!all(lat_valid, na.rm = TRUE)) {
    rlang::warn(
      "Some latitude values outside expected US range (18-72)",
      class = "validation_warning"
    )
  }

  # Check longitude range (warning only - never filter; US territories)
  long_valid <- data$LONG_DECIMAL >= -180 & data$LONG_DECIMAL <= -64
  if (!all(long_valid, na.rm = TRUE)) {
    rlang::warn(
      "Some longitude values outside expected US range (-180 to -64)",
      class = "validation_warning"
    )
  }

  invisible(data)
}
