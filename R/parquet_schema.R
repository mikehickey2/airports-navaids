# parquet_schema.R
# Parquet type coercion for the cleaning layer
#
# Companion to run_cleaning.R, whose write_clean_output() coerces cleaned
# data through coerce_to_schema() before writing Parquet. The schema
# constants themselves (airports_parquet_schema, navaids_parquet_schema)
# live beside the *_columns constants in clean_airports.R/clean_navaids.R.
# Consumers of the full cleaning path source this file alongside the other
# three.
#
# Condition classes keep the cleaning layer's clean_data_* prefix.

library(checkmate)
library(rlang)

#' Parse an FAA date string to Date
#'
#' FAA NASR CSVs write dates as YYYY/MM/DD. Aborts on any value that fails to
#' parse rather than propagating NA, so a format change in the source data is
#' caught at the cycle it appears in.
#'
#' @param x Character vector of FAA date strings
#' @return Date vector of the same length
#' @keywords internal
parse_faa_date <- function(x) {
  parsed <- as.Date(x, format = "%Y/%m/%d")
  unparsed <- unique(x[is.na(parsed) & !is.na(x)])
  if (length(unparsed) > 0) {
    rlang::abort(
      c(
        "Could not parse FAA date values",
        x = paste("Unparsed:", paste(utils::head(unparsed, 5), collapse = ", ")),
        i = "Expected YYYY/MM/DD"
      ),
      class = "clean_data_date_parse_error"
    )
  }
  parsed
}

#' Coerce values to a numeric Parquet type, failing loudly on drift
#'
#' A cycle where read.csv() infers a numeric column as character is exactly
#' the cycle where blind as.integer()/as.double() would mint NAs with only a
#' warning, or truncate fractional values silently. Blank strings map to NA
#' first, matching what read.csv() produces natively when it infers the
#' column as numeric; anything else that fails to parse aborts, as does a
#' fractional value declared INT32.
#'
#' @param x Vector to coerce
#' @param type One of "INT32" or "DOUBLE"
#' @return Integer or double vector of the same length
#' @keywords internal
coerce_numeric <- function(x, type) {
  if (is.character(x)) {
    x[!nzchar(trimws(x))] <- NA_character_
  }
  converted <- withCallingHandlers(
    as.double(x),
    warning = function(w) {
      rlang::abort(
        c(
          paste("Could not coerce values declared", type),
          x = conditionMessage(w)
        ),
        class = "clean_data_coercion_error"
      )
    }
  )
  if (type == "DOUBLE") {
    return(converted)
  }
  fractional <- !is.na(converted) & converted != trunc(converted)
  if (any(fractional)) {
    rlang::abort(
      c(
        "Fractional values cannot be declared INT32",
        x = paste(
          "Example:", utils::head(converted[fractional], 1)
        )
      ),
      class = "clean_data_coercion_error"
    )
  }
  as.integer(converted)
}

#' Derive read.csv() colClasses from a Parquet schema
#'
#' Pins every STRING-declared column as character at read time, so read.csv()
#' cannot infer an all-digit identifier (e.g. SITE_NO "00103.") as numeric and
#' destroy leading zeros before the cleaning layer sees it. Non-STRING columns
#' are left to inference; coerce_to_schema() pins those on the way out.
#'
#' @param schema Named character vector: column name to Parquet type
#' @return Named character vector suitable for read.csv()'s colClasses
#' @keywords internal
schema_col_classes <- function(schema) {
  checkmate::assert_character(schema, names = "named", any.missing = FALSE)

  cols <- names(schema)[schema == "STRING"]
  stats::setNames(rep("character", length(cols)), cols)
}

#' Coerce a cleaned data frame to its declared Parquet schema
#'
#' Pins types so the written Parquet file does not inherit read.csv()'s
#' per-cycle type inference. Aborts when the data and the schema disagree on
#' which columns exist, so a column added or dropped upstream fails loudly.
#'
#' @param data Data frame of cleaned data
#' @param schema Named character vector: column name to Parquet type
#' @return The data frame with each column coerced to its declared type
#' @keywords internal
coerce_to_schema <- function(data, schema) {
  checkmate::assert_data_frame(data, min.rows = 1)
  checkmate::assert_character(schema, names = "named", any.missing = FALSE)

  missing_cols <- setdiff(names(schema), names(data))
  extra_cols <- setdiff(names(data), names(schema))
  if (length(missing_cols) > 0 || length(extra_cols) > 0) {
    rlang::abort(
      c(
        "Data columns do not match the declared Parquet schema",
        x = paste("Missing from data:", paste(missing_cols, collapse = ", ")),
        x = paste("Not in schema:", paste(extra_cols, collapse = ", "))
      ),
      class = "clean_data_schema_mismatch"
    )
  }

  coercers <- list(
    DATE = parse_faa_date,
    STRING = as.character,
    INT32 = function(x) coerce_numeric(x, "INT32"),
    DOUBLE = function(x) coerce_numeric(x, "DOUBLE")
  )

  unknown <- setdiff(unique(unname(schema)), names(coercers))
  if (length(unknown) > 0) {
    rlang::abort(
      c(
        "Unsupported Parquet type in schema",
        x = paste("Unknown:", paste(unknown, collapse = ", "))
      ),
      class = "clean_data_schema_type_error"
    )
  }

  data[names(schema)] <- Map(
    function(col, type) coercers[[type]](data[[col]]),
    names(schema), unname(schema)
  )
  data[names(schema)]
}
