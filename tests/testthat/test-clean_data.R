# test-clean_data.R
# Tests for R/clean_data.R functions

# Source the refactored functions
source_project_file("clean_data.R")

test_that("clean_navaids validates file path exists", {
  expect_error(
    clean_navaids("/nonexistent/path/NAV_BASE.csv"),
    class = "simpleError"
  )
})

test_that("clean_navaids returns expected columns", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "NAV_BASE.csv")

  # Create minimal valid test data
  test_data <- data.frame(
    stringsAsFactors = FALSE,
    EFF_DATE = "12/19/2024",
    NAV_ID = "LAX",
    NAV_TYPE = "VOR",
    STATE_CODE = "CA",
    CITY = "Los Angeles",
    COUNTRY_CODE = "US",
    NAME = "Los Angeles VOR",
    STATE_NAME = "California",
    REGION_CODE = "AWP",
    LAT_HEMIS = "N", LAT_DEG = 33L, LAT_MIN = 56L, LAT_SEC = "33.00",
    LAT_DECIMAL = 33.94,
    LONG_HEMIS = "W", LONG_DEG = 118L, LONG_MIN = 24L, LONG_SEC = "29.00",
    LONG_DECIMAL = -118.41,
    ELEV = 128,
    MAG_VARN = 13.0, MAG_VARN_HEMIS = "E", MAG_VARN_YEAR = 2020L,
    ALT_CODE = "LOW",
    EXTRA_COL = "should be dropped"
  )

  write.csv(test_data, temp_file, row.names = FALSE)

  result <- clean_navaids(temp_file)

  expect_equal(sort(names(result)), sort(navaids_columns))
  expect_false("EXTRA_COL" %in% names(result))
})

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

test_that("navaids validation warns on low row count", {
  data <- sample_navaids(3) # 3 rows, all NAV_TYPE values valid
  names(data) <- toupper(names(data))

  expect_warning(
    validate_cleaned_data(data, "navaids"),
    class = "validation_warning"
  )
})

test_that("navaids validation warns on unexpected NAV_TYPE", {
  data <- sample_navaids(3)
  names(data) <- toupper(names(data))
  data$NAV_TYPE <- c("VOR", "NDB", "MADE_UP_TYPE")

  # Low row count also warns; collect all warnings, then check content
  warnings_seen <- character()
  withCallingHandlers(
    validate_cleaned_data(data, "navaids"),
    validation_warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("MADE_UP_TYPE", warnings_seen)))
})
