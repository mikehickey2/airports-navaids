# test-run_cleaning.R
# Tests for R/run_cleaning.R functions

# run_cleaning() drives the full cleaning path, so this file sources the
# domain files as well as the orchestrator under test.
source_project_file("clean_airports.R")
source_project_file("clean_navaids.R")
source_project_file("run_cleaning.R")

# sample_airports() returns lowercase column names; the production schemas are
# keyed to the cleaned data's uppercase names. Same columns, different case.
fixture_schema <- function() {
  stats::setNames(
    unname(airports_parquet_schema),
    tolower(names(airports_parquet_schema))
  )
}

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
  expect_true(file.exists(file.path(work_dir, "data", "clean", "airports.parquet")))
  expect_true(file.exists(file.path(work_dir, "data", "clean", "navaids.parquet")))

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

test_that("write_clean_output writes both csv and parquet", {
  out_dir <- file.path(withr::local_tempdir(), "clean")
  data <- sample_airports(3)

  paths <- write_clean_output(data, "airports", fixture_schema(), dir = out_dir)

  expect_true(file.exists(paths[["csv"]]))
  expect_true(file.exists(paths[["parquet"]]))
  expect_equal(basename(paths[["csv"]]), "airports.csv")
  expect_equal(basename(paths[["parquet"]]), "airports.parquet")
})

test_that("write_clean_output parquet round-trips to the same data", {
  out_dir <- file.path(withr::local_tempdir(), "clean")
  data <- sample_airports(3)

  paths <- write_clean_output(data, "airports", fixture_schema(), dir = out_dir)
  round_tripped <- nanoparquet::read_parquet(paths[["parquet"]])
  expected <- coerce_to_schema(data, fixture_schema())

  expect_equal(dim(round_tripped), dim(data))
  expect_equal(names(round_tripped), names(data))
  expect_equal(
    as.data.frame(round_tripped), as.data.frame(expected),
    ignore_attr = TRUE
  )
})

test_that("write_clean_output parquet preserves types that csv flattens to text", {
  out_dir <- file.path(withr::local_tempdir(), "clean")
  data <- sample_airports(3)

  paths <- write_clean_output(data, "airports", fixture_schema(), dir = out_dir)
  round_tripped <- nanoparquet::read_parquet(paths[["parquet"]])

  expect_s3_class(round_tripped$eff_date, "Date")
  expect_type(round_tripped$lat_decimal, "double")
  expect_type(round_tripped$mag_varn_year, "integer")
  expect_type(round_tripped$arpt_id, "character")
})

test_that("write_clean_output rejects a non-data-frame", {
  out_dir <- file.path(withr::local_tempdir(), "clean")

  expect_error(
    write_clean_output("not a data frame", "airports", fixture_schema(),
                       dir = out_dir),
    "Assertion on 'data' failed"
  )
})

test_that("write_clean_output rejects an empty data frame", {
  out_dir <- file.path(withr::local_tempdir(), "clean")
  data <- sample_airports(3)

  expect_error(
    write_clean_output(data[0, ], "airports", fixture_schema(), dir = out_dir),
    "Assertion on 'data' failed"
  )
})

test_that("write_clean_output rejects a name that could escape the output dir", {
  out_dir <- file.path(withr::local_tempdir(), "clean")
  data <- sample_airports(3)

  expect_error(
    write_clean_output(data, "../escape", fixture_schema(), dir = out_dir),
    "Assertion on 'name' failed"
  )
})

test_that("write_clean_output rejects a non-scalar name", {
  out_dir <- file.path(withr::local_tempdir(), "clean")
  data <- sample_airports(3)

  expect_error(
    write_clean_output(data, c("airports", "navaids"), fixture_schema(),
                       dir = out_dir),
    "Assertion on 'name' failed"
  )
})
