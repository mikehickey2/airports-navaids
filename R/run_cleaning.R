# run_cleaning.R
# Cleaning-stage orchestration: runs the full clean step for both datasets
#
# Domain cleaning lives in clean_airports.R and clean_navaids.R, and Parquet
# type coercion in parquet_schema.R; this file holds run_cleaning(),
# write_clean_output(), the validate_cleaned_data() dispatcher, and the
# shared raw-directory helpers. Consumers of the full cleaning path source
# all four files.
#
# Condition classes across the cleaning layer keep the historical
# clean_data_* prefix (e.g. clean_data_schema_error): it is the cleaning
# layer's condition namespace, retained deliberately when clean_data.R was
# renamed (issue #24) so the condition contract stayed stable.
#
# Usage:
#   source("R/clean_airports.R")
#   source("R/clean_navaids.R")
#   source("R/parquet_schema.R")
#   source("R/run_cleaning.R")
#   dirs <- find_raw_data_dirs("data/raw")
#   run_cleaning(dirs$apt_dir, dirs$nav_dir)
#
# Or run directly to clean current raw data (airports and navaids):
#   Rscript R/run_cleaning.R

library(checkmate)
library(rlang)

#' Run data cleaning step of pipeline
#'
#' Cleans airports and navaids data from raw directories.
#'
#' @param apt_dir Path to APT directory
#' @param nav_dir Path to NAV directory
#' @return Named list with airports, navaids, airports_count, navaids_count
#' @keywords internal
run_cleaning <- function(apt_dir, nav_dir) {
  checkmate::assert_directory_exists(apt_dir)
  checkmate::assert_directory_exists(nav_dir)

  # Clean airports
  apt_path <- file.path(apt_dir, "APT_BASE.csv")
  airports <- clean_airports(apt_path)
  validate_cleaned_data(airports, "airports")

  write_clean_output(airports, "airports", airports_parquet_schema)

  # Clean navaids
  nav_path <- file.path(nav_dir, "NAV_BASE.csv")
  navaids <- clean_navaids(nav_path)
  validate_cleaned_data(navaids, "navaids")

  write_clean_output(navaids, "navaids", navaids_parquet_schema)

  # Remove extra files
  remove_extra_files(apt_dir, nav_dir)

  list(
    airports = airports,
    navaids = navaids,
    airports_count = nrow(airports),
    navaids_count = nrow(navaids)
  )
}

#' Write a cleaned dataset to both CSV and Parquet
#'
#' Both files always contain identical rows and columns. Parquet is written
#' with nanoparquet, chosen over arrow because it has no transitive
#' dependencies and no system requirements, so a CI source-build fallback
#' costs seconds rather than tens of minutes.
#'
#' @param data Data frame of cleaned data, at least one row
#' @param name Dataset name used as the file stem, lowercase and underscores
#' @param schema Named character vector of declared Parquet types, from
#'   airports_parquet_schema or navaids_parquet_schema
#' @param dir Output directory, created if it does not exist
#' @return Named character vector of the two written paths, invisibly
#' @keywords internal
write_clean_output <- function(data, name, schema, dir = "data/clean") {
  checkmate::assert_data_frame(data, min.rows = 1)
  checkmate::assert_string(name, pattern = "^[a-z_]+$")
  checkmate::assert_character(schema, names = "named", any.missing = FALSE)

  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }

  csv_path <- file.path(dir, paste0(name, ".csv"))
  parquet_path <- file.path(dir, paste0(name, ".parquet"))

  # CSV keeps the untyped form it has always had, so the published CSV does not
  # change. Parquet gets the pinned, coerced types.
  write.csv(data, csv_path, row.names = FALSE)

  # Repetition is pinned OPTIONAL for every column, matching the nullable
  # SQL schema, so nullability cannot drift with which columns happen to
  # carry NA in a given cycle.
  typed <- coerce_to_schema(data, schema)
  declared <- lapply(as.list(schema), function(type) {
    list(type, repetition_type = "OPTIONAL")
  })
  nanoparquet::write_parquet(
    typed, parquet_path,
    schema = do.call(nanoparquet::parquet_schema, declared)
  )

  message("Wrote ", nrow(data), " ", name, " to ", csv_path, " and ", parquet_path)

  invisible(c(csv = csv_path, parquet = parquet_path))
}

#' Validate cleaned data against schema rules
#'
#' Dispatches to validate_airports() (clean_airports.R) or
#' validate_navaids() (clean_navaids.R) based on schema_type.
#'
#' @param data Tibble of cleaned data
#' @param schema_type One of "airports" or "navaids"
#' @return The input data (invisibly) if valid, otherwise aborts
#' @export
validate_cleaned_data <- function(data,
                                  schema_type = c("airports", "navaids")) {
  checkmate::assert_data_frame(data, min.rows = 1)
  schema_type <- match.arg(schema_type)

  message("Validating ", schema_type, " data...")

  if (schema_type == "airports") {
    validate_airports(data)
  } else {
    validate_navaids(data)
  }

  message("Validation complete for ", schema_type)
  invisible(data)
}

#' Find raw data directories
#'
#' Searches for APT and NAV directories in the raw data folder.
#'
#' @param raw_dir Path to raw data directory (default: "data/raw")
#' @return Named list with apt_dir and nav_dir paths
#' @keywords internal
find_raw_data_dirs <- function(raw_dir = "data/raw") {
  checkmate::assert_directory_exists(raw_dir)

  raw_dirs <- list.dirs(raw_dir, full.names = TRUE, recursive = FALSE)
  apt_dir <- raw_dirs[grepl("_APT_CSV$", raw_dirs)]
  nav_dir <- raw_dirs[grepl("_NAV_CSV$", raw_dirs)]

  if (length(apt_dir) == 0 || length(nav_dir) == 0) {
    rlang::abort(
      c(
        "Could not find APT or NAV directories",
        i = paste("Searched in:", raw_dir)
      ),
      class = "clean_data_missing_dirs"
    )
  }

  # Use first match if multiple exist
  list(
    apt_dir = apt_dir[1],
    nav_dir = nav_dir[1]
  )
}

#' Remove extra CSV files from raw data directories
#'
#' @param apt_dir Path to APT directory
#' @param nav_dir Path to NAV directory
#' @return Number of files removed
#' @keywords internal
remove_extra_files <- function(apt_dir, nav_dir) {
  apt_extra <- c(
    "APT_ATT.csv", "APT_ARS.csv", "APT_CON.csv",
    "APT_RMK.csv", "APT_RWY_END.csv", "APT_RWY.csv"
  )
  nav_extra <- c("NAV_CKPT.csv", "NAV_RMK.csv")

  apt_files <- file.path(apt_dir, apt_extra)
  nav_files <- file.path(nav_dir, nav_extra)
  all_files <- c(apt_files, nav_files)
  files_to_remove <- all_files[file.exists(all_files)]

  if (length(files_to_remove) > 0) {
    file.remove(files_to_remove)
    message("Removed ", length(files_to_remove), " extra CSV files")
  }

  length(files_to_remove)
}

# --- Main execution (only when run directly) ---
if (sys.nframe() == 0L) {
  source("R/clean_airports.R")
  source("R/clean_navaids.R")
  source("R/parquet_schema.R")

  message("Running run_cleaning.R as main script...")

  dirs <- find_raw_data_dirs("data/raw")
  run_cleaning(dirs$apt_dir, dirs$nav_dir)

  message("Data cleaning complete!")
}
