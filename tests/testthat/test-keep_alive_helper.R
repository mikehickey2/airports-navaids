# Diagnostics should identify the workflow layout or fixture that needs repair.

test_that("workflow extraction explains missing or empty run blocks", {
  for (lines in list(character(), "        run: |", rep("        run: |", 2))) {
    rlang::local_bindings(
      readLines = function(...) lines,
      .env = environment(keep_alive_workflow)
    )
    expect_error(
      keep_alive_workflow(),
      "Expected one nonempty 'run: |' block in keep-alive.yml",
      fixed = TRUE, class = "rlang_error"
    )
  }
})

test_that("workflow extraction explains unsupported indentation", {
  rlang::local_bindings(
    readLines = function(...) c("        run: |", "  echo changed"),
    .env = environment(keep_alive_workflow)
  )
  expect_error(
    keep_alive_workflow(),
    "Expected ten-space indentation after 'run: |' in keep-alive.yml",
    fixed = TRUE, class = "rlang_error"
  )
})

test_that("workflow extraction identifies missing or duplicate limits", {
  original <- readLines(file.path(
    project_root(), ".github/workflows/keep-alive.yml"
  ))
  for (field in c("MIN_AIRPORTS", "timeout-minutes")) {
    index <- grep(paste0(field, ":"), original)
    variants <- list(original[-index], append(original, original[index], 1))
    for (lines in variants) {
      rlang::local_bindings(
        readLines = function(...) lines,
        .env = environment(keep_alive_workflow)
      )
      expect_error(
        keep_alive_workflow(),
        paste0("Expected one valid ", field, " setting in keep-alive.yml"),
        fixed = TRUE, class = "rlang_error"
      )
    }
  }
})

test_that("fixture setup explains a failed copy", {
  rlang::local_bindings(
    file.copy = function(...) FALSE,
    .env = environment(run_keep_alive)
  )
  expect_error(
    run_keep_alive("status=206 count=19411"),
    "Could not copy the keep-alive curl/sleep fixtures; check fixture paths",
    fixed = TRUE, class = "rlang_error"
  )
})
