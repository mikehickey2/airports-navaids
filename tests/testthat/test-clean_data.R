# test-clean_data.R
# Tests for R/clean_data.R functions

# Source the refactored functions
source_project_file("clean_data.R")

test_that("clean_airports validates file path exists", {
  expect_error(
    clean_airports("/nonexistent/path/APT_BASE.csv"),
    class = "simpleError"
  )
})

test_that("clean_airports retains 4-char ARPT_IDs and all site types", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "APT_BASE.csv")

  test_data <- data.frame(stringsAsFactors = FALSE,
    EFF_DATE = "12/19/2024",
    SITE_NO = c("00001", "00002", "00003"),
    SITE_TYPE_CODE = c("A", "H", "A"),
    STATE_CODE = c("CA", "AL", "AL"),
    ARPT_ID = c("LAX", "0AL1", "AL10"),  # 4-char private LID AL10 retained
    CITY = c("Los Angeles", "Helitown", "Gurley"),
    COUNTRY_CODE = "US",
    STATE_NAME = c("California", "Alabama", "Alabama"),
    COUNTY_NAME = c("Los Angeles", "X", "Madison"),
    ARPT_NAME = c("Los Angeles Intl", "Helipad", "Frerichs"),
    LAT_DEG = c(33L, 34L, 34L), LAT_MIN = c(56L, 0L, 42L),
    LAT_SEC = c("33.00", "0.00", "0.00"), LAT_HEMIS = "N",
    LAT_DECIMAL = c(33.94, 34.0, 34.7),
    LONG_DEG = c(118L, 86L, 86L), LONG_MIN = c(24L, 0L, 21L),
    LONG_SEC = c("29.00", "0.00", "0.00"), LONG_HEMIS = "W",
    LONG_DECIMAL = c(-118.41, -86.0, -86.35),
    ELEV = c(128, 600, 700),
    ELEV_METHOD_CODE = "S",
    MAG_VARN = c(13.0, 2.0, 2.0), MAG_HEMIS = "W", MAG_VARN_YEAR = 2020L,
    ICAO_ID = c("KLAX", "", ""),
    FACILITY_USE_CODE = c("PU", "PR", "PR")
  )
  write.csv(test_data, temp_file, row.names = FALSE)

  result <- clean_airports(temp_file)

  expect_true("AL10" %in% result$ARPT_ID)   # 4-char private LID retained
  expect_true("0AL1" %in% result$ARPT_ID)   # heliport retained
  expect_equal(nrow(result), 3)             # no rows dropped
})

test_that("clean_airports maps PU/PR to public/private", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "APT_BASE.csv")
  test_data <- data.frame(stringsAsFactors = FALSE,
    EFF_DATE = "12/19/2024", SITE_NO = c("00001", "00002"),
    SITE_TYPE_CODE = "A", STATE_CODE = c("CA", "AL"),
    ARPT_ID = c("LAX", "AL10"), CITY = c("Los Angeles", "Gurley"),
    COUNTRY_CODE = "US", STATE_NAME = c("California", "Alabama"),
    COUNTY_NAME = c("Los Angeles", "Madison"),
    ARPT_NAME = c("Los Angeles Intl", "Frerichs"),
    LAT_DEG = c(33L, 34L), LAT_MIN = c(56L, 42L),
    LAT_SEC = c("33.00", "0.00"), LAT_HEMIS = "N",
    LAT_DECIMAL = c(33.94, 34.7),
    LONG_DEG = c(118L, 86L), LONG_MIN = c(24L, 21L),
    LONG_SEC = c("29.00", "0.00"), LONG_HEMIS = "W",
    LONG_DECIMAL = c(-118.41, -86.35),
    ELEV = c(128, 700), ELEV_METHOD_CODE = "S",
    MAG_VARN = c(13.0, 2.0), MAG_HEMIS = "W", MAG_VARN_YEAR = 2020L,
    ICAO_ID = c("KLAX", ""), FACILITY_USE_CODE = c("PU", "PR")
  )
  write.csv(test_data, temp_file, row.names = FALSE)

  result <- clean_airports(temp_file)

  expect_equal(result$facility_use[result$ARPT_ID == "LAX"], "public")
  expect_equal(result$facility_use[result$ARPT_ID == "AL10"], "private")
})

test_that("clean_airports output has facility_use, not facility_use_code", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "APT_BASE.csv")
  test_data <- data.frame(stringsAsFactors = FALSE,
    EFF_DATE = "12/19/2024", SITE_NO = "00001", SITE_TYPE_CODE = "A",
    STATE_CODE = "CA", ARPT_ID = "LAX", CITY = "Los Angeles",
    COUNTRY_CODE = "US", STATE_NAME = "California", COUNTY_NAME = "LA",
    ARPT_NAME = "Los Angeles Intl",
    LAT_DEG = 33L, LAT_MIN = 56L, LAT_SEC = "33.00", LAT_HEMIS = "N",
    LAT_DECIMAL = 33.94,
    LONG_DEG = 118L, LONG_MIN = 24L, LONG_SEC = "29.00", LONG_HEMIS = "W",
    LONG_DECIMAL = -118.41,
    ELEV = 128, ELEV_METHOD_CODE = "S",
    MAG_VARN = 13.0, MAG_HEMIS = "E", MAG_VARN_YEAR = 2020L,
    ICAO_ID = "KLAX", FACILITY_USE_CODE = "PU"
  )
  write.csv(test_data, temp_file, row.names = FALSE)

  result <- clean_airports(temp_file)

  expect_true("facility_use" %in% names(result))
  expect_false("facility_use_code" %in% tolower(names(result)))
  expect_false("FACILITY_USE_CODE" %in% names(result))
})

test_that("clean_airports aborts on unknown facility-use code", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "APT_BASE.csv")
  test_data <- data.frame(stringsAsFactors = FALSE,
    EFF_DATE = "12/19/2024", SITE_NO = "00001", SITE_TYPE_CODE = "A",
    STATE_CODE = "CA", ARPT_ID = "LAX", CITY = "Los Angeles",
    COUNTRY_CODE = "US", STATE_NAME = "California", COUNTY_NAME = "LA",
    ARPT_NAME = "Los Angeles Intl",
    LAT_DEG = 33L, LAT_MIN = 56L, LAT_SEC = "33.00", LAT_HEMIS = "N",
    LAT_DECIMAL = 33.94,
    LONG_DEG = 118L, LONG_MIN = 24L, LONG_SEC = "29.00", LONG_HEMIS = "W",
    LONG_DECIMAL = -118.41,
    ELEV = 128, ELEV_METHOD_CODE = "S",
    MAG_VARN = 13.0, MAG_HEMIS = "E", MAG_VARN_YEAR = 2020L,
    ICAO_ID = "KLAX", FACILITY_USE_CODE = "ZZ"  # invalid code
  )
  write.csv(test_data, temp_file, row.names = FALSE)

  expect_error(
    clean_airports(temp_file),
    class = "clean_data_facility_use_error"
  )
})

test_that("clean_airports returns expected columns", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "APT_BASE.csv")

  # Create minimal valid test data
  test_data <- data.frame(stringsAsFactors = FALSE,
    EFF_DATE = "12/19/2024",
    SITE_NO = "00001",
    SITE_TYPE_CODE = "A",
    STATE_CODE = "CA",
    ARPT_ID = "LAX",
    CITY = "Los Angeles",
    COUNTRY_CODE = "US",
    STATE_NAME = "California",
    COUNTY_NAME = "Los Angeles",
    ARPT_NAME = "Los Angeles Intl",
    LAT_DEG = 33L, LAT_MIN = 56L, LAT_SEC = "33.00", LAT_HEMIS = "N",
    LAT_DECIMAL = 33.94,
    LONG_DEG = 118L, LONG_MIN = 24L, LONG_SEC = "29.00", LONG_HEMIS = "W",
    LONG_DECIMAL = -118.41,
    ELEV = 128,
    ELEV_METHOD_CODE = "S",
    MAG_VARN = 13.0, MAG_HEMIS = "E", MAG_VARN_YEAR = 2020L,
    ICAO_ID = "KLAX",
    FACILITY_USE_CODE = "PU",
    EXTRA_COL = "should be dropped"  # Extra column not in schema
  )

  write.csv(test_data, temp_file, row.names = FALSE)

  result <- clean_airports(temp_file)

  # Should have exactly the expected columns
  expect_equal(sort(names(result)), sort(airports_columns))

  # Extra column should be dropped
  expect_false("EXTRA_COL" %in% names(result))
})

test_that("clean_airports aborts on missing columns", {
  temp_dir <- withr::local_tempdir()
  temp_file <- file.path(temp_dir, "APT_BASE.csv")

  # Create data missing required columns
  test_data <- data.frame(stringsAsFactors = FALSE,
    EFF_DATE = "12/19/2024",
    ARPT_ID = "LAX"
    # Missing many required columns
  )

  write.csv(test_data, temp_file, row.names = FALSE)

  expect_error(
    clean_airports(temp_file),
    class = "clean_data_schema_error"
  )
})

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
  test_data <- data.frame(stringsAsFactors = FALSE,
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

test_that("validate_cleaned_data accepts 4-char ARPT_IDs", {
  data <- sample_airports(3)
  names(data) <- toupper(names(data))
  names(data)[names(data) == "FACILITY_USE"] <- "facility_use"
  data$ARPT_ID <- c("LAX", "AL10", "0AL1")  # mixed 3/4-char now valid

  result <- withCallingHandlers(
    validate_cleaned_data(data, "airports"),
    validation_warning = function(w) invokeRestart("muffleWarning")
  )
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 3)
  expect_true(all(c("AL10", "0AL1") %in% result$ARPT_ID))
})

test_that("validate_cleaned_data aborts when facility_use column is missing", {
  data <- sample_airports(3)
  names(data) <- toupper(names(data))
  names(data)[names(data) == "FACILITY_USE"] <- "facility_use"
  data$facility_use <- NULL  # remove the column entirely

  expect_error(
    withCallingHandlers(
      validate_cleaned_data(data, "airports"),
      validation_warning = function(w) invokeRestart("muffleWarning")
    ),
    class = "validation_error"
  )
})

test_that("validate_cleaned_data aborts on invalid facility_use", {
  data <- sample_airports(3)
  names(data) <- toupper(names(data))
  names(data)[names(data) == "FACILITY_USE"] <- "facility_use"
  data$facility_use <- c("public", "private", "bogus")

  expect_error(
    withCallingHandlers(
      validate_cleaned_data(data, "airports"),
      validation_warning = function(w) invokeRestart("muffleWarning")
    ),
    class = "validation_error"
  )
})

test_that("validate_cleaned_data warns but does not drop out-of-range coords", {
  data <- sample_airports(2)
  names(data) <- toupper(names(data))
  names(data)[names(data) == "FACILITY_USE"] <- "facility_use"
  data$LAT_DECIMAL <- c(13.4, 33.94)     # Guam-like latitude (< 18) included
  data$LONG_DECIMAL <- c(144.8, -118.4)  # Guam-like longitude (> -64) included

  result <- withCallingHandlers(
    validate_cleaned_data(data, "airports"),
    validation_warning = function(w) invokeRestart("muffleWarning")
  )
  expect_equal(nrow(result), 2)  # nothing filtered
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
