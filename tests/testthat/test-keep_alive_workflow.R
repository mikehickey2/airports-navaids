# Keep the workflow shell under test; curl and sleep are offline Bash fixtures.

test_that("TLS failure recovers after the configured delay", {
  result <- run_keep_alive(c("exit=35", "status=206 count=19411"))
  expect_equal(result$status, 0L, info = paste(result$stdout, result$stderr))
  expect_identical(result$events, c("curl", "sleep", "curl"))
  expect_equal(result$waits, 60)
  expect_match(result$stdout, "Supabase is active. airports rows: 19411", fixed = TRUE)
  expect_match(result$stderr, "curl: (35)", fixed = TRUE)
})

test_that("requests and waits fit within the job timeout", {
  result <- run_keep_alive(c(
    "exit=35", "status=206 count=0", "exit=28", "status=206 count=19411"
  ))
  expect_equal(result$status, 0L, info = paste(result$stdout, result$stderr))
  seconds <- sum(result$waits)
  for (args in result$args) {
    connect <- keep_alive_option(args, "--connect-timeout")
    maximum <- keep_alive_option(args, "--max-time")
    expect_gt(connect, 0)
    expect_lte(connect, maximum)
    seconds <- seconds + maximum
  }
  expect_length(result$args, 4L)
  expect_length(result$waits, 3L)
  expect_lte(seconds, keep_alive_workflow()$timeout - 30)
})

test_that("HTTP error on the low-count recheck still fails", {
  result <- run_keep_alive(c("status=206 count=0", "status=403 count=19411"))
  expect_false(result$status == 0L, info = result$stdout)
  expect_match(result$stdout, "Supabase returned HTTP 403", fixed = TRUE)
  expect_identical(result$events, c("curl", "sleep", "curl"))
})

test_that("healthy responses do not retry", {
  for (status in c(200, 206)) {
    result <- run_keep_alive(paste0("status=", status, " count=19000"))
    expect_equal(result$status, 0L, info = paste("HTTP", status, result$stderr))
    expect_identical(result$events, "curl", info = paste("HTTP", status))
  }
})

test_that("persistent transport failure exhausts the budget", {
  result <- run_keep_alive(rep("exit=35", 3))
  expect_equal(result$status, 35L)
  expect_length(result$args, 3L)
  expect_length(result$waits, 2L)
  expect_match(result$stdout, "Transport retry budget exhausted", fixed = TRUE)
  expect_no_match(result$stdout, "Supabase is active", fixed = TRUE)
})

test_that("every allowlisted transport error can recover", {
  for (code in c(5, 6, 7, 16, 18, 28, 35, 52, 55, 56, 92)) {
    result <- run_keep_alive(c(paste0("exit=", code), "status=206 count=19411"))
    expect_equal(result$status, 0L, info = paste("curl exit", code, result$stderr))
    expect_identical(result$events, c("curl", "sleep", "curl"), info = paste("curl exit", code))
    expect_match(result$stdout, paste("curl exited with code", code), fixed = TRUE)
  }
})

test_that("non-retryable curl errors fail immediately", {
  for (code in c(3, 23, 51, 58, 60, 77)) {
    result <- run_keep_alive(paste0("exit=", code))
    expect_equal(result$status, code, info = paste("curl exit", code))
    expect_identical(result$events, "curl", info = paste("curl exit", code))
    expect_match(result$stdout, "Non-retryable curl failure", fixed = TRUE)
  }
})

test_that("HTTP errors do not use transport retries", {
  for (status in c(401, 403, 429, 500, 502, 503, 504)) {
    result <- run_keep_alive(paste0("status=", status))
    expect_false(result$status == 0L, info = paste("HTTP", status))
    expect_identical(result$events, "curl", info = paste("HTTP", status))
    expect_match(result$stdout, paste("Supabase returned HTTP", status), fixed = TRUE)
  }
})

test_that("invalid counts fail without retry", {
  for (response in c(
    "status=206", "status=206 count=*", "status=206 count=",
    "status=206 count=-1", "status=206 count=abc"
  )) {
    result <- run_keep_alive(response)
    expect_false(result$status == 0L, info = response)
    expect_identical(result$events, "curl", info = response)
    expect_match(result$stdout, "not a number", fixed = TRUE)
  }
})

test_that("the low-count recheck can recover", {
  result <- run_keep_alive(c("status=206 count=18999", "status=206 count=19411"))
  expect_equal(result$status, 0L, info = paste(result$stdout, result$stderr))
  expect_identical(result$events, c("curl", "sleep", "curl"))
  expect_equal(result$waits, 60)
})

test_that("persistent low count fails after one recheck", {
  result <- run_keep_alive(c("status=206 count=0", "status=206 count=18999"))
  expect_false(result$status == 0L)
  expect_match(result$stdout, "still below floor 19000 after retry", fixed = TRUE)
  expect_identical(result$events, c("curl", "sleep", "curl"))
})

test_that("the low-count recheck cannot reuse the previous count", {
  result <- run_keep_alive(c("status=206 count=0", "status=206"))
  expect_false(result$status == 0L)
  expect_match(result$stdout, "not a number", fixed = TRUE)
  expect_identical(result$events, c("curl", "sleep", "curl"))
})

test_that("the transport budget is shared across the low-count recheck", {
  result <- run_keep_alive(c("exit=35", "status=206 count=0", "exit=28", "exit=35"))
  expect_equal(result$status, 35L)
  expect_length(result$args, 4L)
  expect_length(result$waits, 3L)
  expect_match(result$stdout, "Transport retry budget exhausted", fixed = TRUE)
})

test_that("an empty key fails before any network request", {
  result <- run_keep_alive(character(), key = " \n\t")
  expect_false(result$status == 0L)
  expect_identical(result$events, character())
  expect_match(result$stdout, "SUPABASE_PUBLIC_KEY is empty", fixed = TRUE)
})

test_that("requests preserve headers without logging the key", {
  result <- run_keep_alive(c("exit=35", "status=206 count=19411"), key = " test-key\n\t")
  expect_equal(result$status, 0L, info = paste(result$stdout, result$stderr))
  expect_no_match(paste(result$stdout, result$stderr), "test-key", fixed = TRUE)
  for (args in result$args) {
    expect_true("apikey: test-key" %in% args)
    expect_true("Prefer: count=exact" %in% args)
    expect_true("Range: 0-0" %in% args)
    expect_true("https://supabase.invalid/rest/v1/airports?select=id" %in% args)
    expect_true("--no-progress-meter" %in% args)
    expect_false(any(c("-k", "--insecure", "-s", "--silent") %in% args))
  }
})
