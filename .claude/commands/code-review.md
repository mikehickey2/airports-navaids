---
name: code-review
description: Comprehensive code review for R projects
allowed-tools: Bash(Rscript:*), Read, Grep, Glob, WebFetch, Task
---

Conduct a thorough code review of this project.

## Context

- Project rules: @CLAUDE.md
- Current lint status: !`Rscript -e "lintr::lint_dir('R')" 2>&1 | head -50`
- Current test status: !`Rscript -e "testthat::test_dir('tests/testthat', reporter = 'summary')" 2>&1 | tail -20`

## Reference Standards

- Code review best practices: https://roadmap.sh/best-practices/code-review
- R syntax and style: https://r4ds.hadley.nz/

## Review Scope

### 1. R Source Files (R/)
- Function design and organization
- Dependency management (avoid bare `library()` in functions)
- roxygen2 documentation completeness
- checkmate/assertr validation patterns
- tidyverse style compliance
- Line length (target 80, max 110, hard 120), function length (<80 lines)
- Script length (300 soft/mention, 500 hard/action)
- Error/warning handling (no suppression without approval)

### 2. Scripts (scripts/)
- Thin wrapper pattern adherence
- Proper sourcing and dependency loading

### 3. Tests (tests/testthat/)
- testthat edition 3 compliance
- Coverage: positive, negative, edge cases

### 4. SQL Schema (sql/)
- Table definitions and constraints
- RLS policy correctness

## Output Format

1. **Executive Summary:** Overall health assessment
2. **Critical Issues:** Must-fix items
3. **Recommendations:** By category
4. **Style/Lint Report:** Summary of findings
5. **Test Status:** Pass/fail details