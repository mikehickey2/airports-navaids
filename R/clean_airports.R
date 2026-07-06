# clean_airports.R
# Functions for cleaning FAA airport data (APT_BASE.csv)
#
# Companion to clean_navaids.R (navaids domain) and run_cleaning.R, which
# holds the cleaning orchestration and the validate_cleaned_data() dispatcher
# that delegates airports validation to validate_airports() defined here.
# clean_airports() works standalone with only this file sourced; airports
# validation through the dispatcher requires sourcing run_cleaning.R too.
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

  # FAA files use ISO-8859-1 (Latin-1) encoding for special characters
  airports_raw <- read.csv(
    apt_base_path,
    fileEncoding = "ISO-8859-1",
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  # Verify required source columns exist
  missing_cols <- setdiff(airports_source_columns, names(airports_raw))
  if (length(missing_cols) > 0) {
    rlang::abort(
      c(
        "APT_BASE.csv missing required columns",
        x = paste("Missing:", paste(missing_cols, collapse = ", "))
      ),
      class = "clean_data_schema_error"
    )
  }

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
