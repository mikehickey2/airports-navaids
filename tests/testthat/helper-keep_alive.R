# Offline harness for the actual keep-alive workflow shell, not a reimplementation.

keep_alive_workflow <- function() {
  path <- file.path(project_root(), ".github/workflows/keep-alive.yml")
  lines <- readLines(path)
  block <- grep("^        run: \\|$", lines)
  stopifnot(length(block) == 1L, block < length(lines))
  body <- lines[seq.int(block + 1L, length(lines))]
  stopifnot(all(!nzchar(body) | startsWith(body, "          ")))
  scalar <- function(pattern) {
    value <- grep(pattern, lines, value = TRUE)
    stopifnot(length(value) == 1L)
    sub(pattern, "\\1", value)
  }
  list(
    script = sub("^          ", "", body),
    floor = scalar("^      MIN_AIRPORTS: '([0-9]+)'$"),
    timeout = as.numeric(scalar("^    timeout-minutes: ([0-9]+)$")) * 60
  )
}

run_keep_alive <- function(responses, key = "test-key") {
  workflow <- keep_alive_workflow()
  root <- withr::local_tempdir(pattern = "keep-alive-test-")
  writeLines(responses, file.path(root, "responses"))
  script <- file.path(root, "probe.sh")
  writeLines(workflow$script, script)
  fixtures <- file.path(project_root(), "tests/testthat/fixtures/keep-alive")
  tools <- file.path(root, c("curl", "sleep"))
  stopifnot(all(file.copy(file.path(fixtures, c("curl", "sleep")), tools)))
  Sys.chmod(tools, mode = "0700")
  result <- processx::run(
    "bash", c("-e", script),
    wd = root,
    env = c(
      PATH = paste(root, Sys.getenv("PATH"), sep = .Platform$path.sep),
      HOME = root, TMPDIR = root, RUNNER_TEMP = root, SCENARIO_DIR = root,
      SUPABASE_KEY = key, TABLE_URL = "https://supabase.invalid/rest/v1/airports",
      MIN_AIRPORTS = workflow$floor
    ),
    error_on_status = FALSE, timeout = 10
  )
  trace <- file.path(root, "trace")
  events <- if (file.exists(trace)) readLines(trace) else character()
  calls <- sum(startsWith(events, "curl\t"))
  result$events <- sub("\t.*$", "", events)
  result$waits <- as.numeric(sub("^sleep\t", "", events[startsWith(events, "sleep\t")]))
  result$args <- lapply(seq_len(calls), function(i) {
    readLines(file.path(root, paste0("args-", i)))
  })
  testthat::expect_length(list.files(root, pattern = "^keep-alive\\."), 0L)
  result
}

keep_alive_option <- function(args, name) {
  testthat::expect_true(name %in% args, info = name)
  as.numeric(args[match(name, args) + 1L])
}
