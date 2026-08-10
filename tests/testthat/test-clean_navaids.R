# test-clean_navaids.R
# Tests for R/clean_navaids.R functions

# clean_navaids.R defines the navaids functions; parquet_schema.R provides
# schema_col_classes() for the read-time pin; run_cleaning.R defines the
# validate_cleaned_data() dispatcher that delegates to validate_navaids().
source_project_file("parquet_schema.R")
source_project_file("clean_navaids.R")
source_project_file("run_cleaning.R")

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

test_that("clean_navaids keeps an all-digit NAV_ID as character", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "NAV_BASE.csv")

  test_data <- data.frame(
    stringsAsFactors = FALSE,
    EFF_DATE = "2024/12/19",
    NAV_ID = c("090", "123"),
    NAV_TYPE = "VOR",
    STATE_CODE = "CA",
    CITY = "Los Angeles",
    COUNTRY_CODE = "US",
    NAME = "Test VOR",
    STATE_NAME = "California",
    REGION_CODE = "AWP",
    LAT_HEMIS = "N", LAT_DEG = 33L, LAT_MIN = 56L, LAT_SEC = "33.00",
    LAT_DECIMAL = 33.94,
    LONG_HEMIS = "W", LONG_DEG = 118L, LONG_MIN = 24L, LONG_SEC = "29.00",
    LONG_DECIMAL = -118.41,
    ELEV = 128,
    MAG_VARN = 13.0, MAG_VARN_HEMIS = "E", MAG_VARN_YEAR = 2020L,
    ALT_CODE = "LOW"
  )

  write.csv(test_data, temp_file, row.names = FALSE)

  expect_no_warning(result <- clean_navaids(temp_file))

  expect_type(result$NAV_ID, "character")
  expect_identical(result$NAV_ID, c("090", "123"))
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
