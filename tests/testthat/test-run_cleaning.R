# test-run_cleaning.R
# Tests for R/run_cleaning.R functions

# run_cleaning() drives the full cleaning path, so this file sources the
# domain files as well as the orchestrator under test.
source_project_file("clean_airports.R")
source_project_file("clean_navaids.R")
source_project_file("run_cleaning.R")

test_that("validate_cleaned_data requires valid schema_type", {
  data <- sample_airports(3)

  expect_error(
    validate_cleaned_data(data, "invalid_type"),
    "arg"
  )
})

test_that("find_raw_data_dirs validates directory exists", {
  expect_error(
    find_raw_data_dirs("/nonexistent/directory"),
    class = "simpleError"
  )
})

test_that("find_raw_data_dirs aborts when no APT/NAV dirs found", {
  temp_dir <- withr::local_tempdir()

  expect_error(
    find_raw_data_dirs(temp_dir),
    class = "clean_data_missing_dirs"
  )
})

test_that("remove_extra_files removes expected files", {
  temp_dir <- withr::local_tempdir()

  # Create APT and NAV subdirectories
  apt_dir <- file.path(temp_dir, "APT_CSV")
  nav_dir <- file.path(temp_dir, "NAV_CSV")
  dir.create(apt_dir)
  dir.create(nav_dir)

  # Create the extra files that should be removed
  apt_extra <- c("APT_ATT.csv", "APT_ARS.csv", "APT_CON.csv")
  nav_extra <- c("NAV_CKPT.csv", "NAV_RMK.csv")

  for (f in apt_extra) file.create(file.path(apt_dir, f))
  for (f in nav_extra) file.create(file.path(nav_dir, f))

  # Verify files exist before removal
  expect_equal(length(list.files(apt_dir)), 3)
  expect_equal(length(list.files(nav_dir)), 2)

  # Remove extra files
  result <- remove_extra_files(apt_dir, nav_dir)

  # Should have removed 5 files

  expect_equal(result, 5)

  # Directories should now be empty
  expect_equal(length(list.files(apt_dir)), 0)
  expect_equal(length(list.files(nav_dir)), 0)
})

test_that("remove_extra_files handles missing files gracefully", {
  temp_dir <- withr::local_tempdir()

  # Create empty APT and NAV subdirectories
  apt_dir <- file.path(temp_dir, "APT_CSV")
  nav_dir <- file.path(temp_dir, "NAV_CSV")
  dir.create(apt_dir)
  dir.create(nav_dir)

  # No files to remove
  result <- remove_extra_files(apt_dir, nav_dir)

  expect_equal(result, 0)
})

test_that("run_cleaning cleans both datasets end to end", {
  raw_dir <- create_test_raw_data_dir()
  dirs <- find_raw_data_dirs(raw_dir)

  work_dir <- withr::local_tempdir()
  withr::local_dir(work_dir)

  warnings_seen <- character()
  result <- withCallingHandlers(
    run_cleaning(dirs$apt_dir, dirs$nav_dir),
    validation_warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  expect_equal(result$airports_count, 4)
  expect_equal(result$navaids_count, 3)
  expect_true(file.exists(file.path(work_dir, "data", "clean", "airports.csv")))
  expect_true(file.exists(file.path(work_dir, "data", "clean", "navaids.csv")))

  # Both validators ran: exactly the two row-count warnings, nothing else
  expect_length(warnings_seen, 2)
  expect_true(any(grepl("18000 airports", warnings_seen)))
  expect_true(any(grepl("1000 navaids", warnings_seen)))
})

test_that("coerce_to_schema pins declared types", {
  data <- sample_airports(3)
  data$eff_date <- "2024/12/19"
  schema <- c(eff_date = "DATE", arpt_id = "STRING", lat_deg = "INT32",
              lat_decimal = "DOUBLE")

  result <- coerce_to_schema(data[names(schema)], schema)

  expect_s3_class(result$eff_date, "Date")
  expect_type(result$arpt_id, "character")
  expect_type(result$lat_deg, "integer")
  expect_type(result$lat_decimal, "double")
  expect_equal(names(result), names(schema))
})

test_that("coerce_to_schema aborts when data and schema disagree", {
  data <- sample_airports(3)

  expect_error(
    coerce_to_schema(data, c(eff_date = "DATE")),
    class = "clean_data_schema_mismatch"
  )
})

test_that("coerce_to_schema aborts on an unsupported type", {
  data <- sample_airports(3)["arpt_id"]

  expect_error(
    coerce_to_schema(data, c(arpt_id = "BLOB")),
    class = "clean_data_schema_type_error"
  )
})

test_that("parse_faa_date aborts rather than returning NA", {
  expect_error(
    parse_faa_date(c("2024/12/19", "19-12-2024")),
    class = "clean_data_date_parse_error"
  )
})

test_that("airports schema covers exactly the cleaned columns", {
  expect_setequal(names(airports_parquet_schema), airports_columns)
})

test_that("navaids schema covers exactly the cleaned columns", {
  expect_setequal(names(navaids_parquet_schema), navaids_columns)
})
