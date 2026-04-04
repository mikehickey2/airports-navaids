---
name: orient
description: Build project context at session start - reviews documentation, scripts, git history, and data state
allowed-tools: Bash(git:*), Read, Glob
---

# Orient

Build comprehensive project context for the FAA Airports & Navaids pipeline.

Run this command at the start of each Claude Code session to establish context.

## Step 1: Read Project Documentation

Read these files:
- `CLAUDE.md` - Project rules, coding standards, and schema documentation
- `README.md` - Project overview and setup instructions
- `CONTRIBUTING.md` - Contribution guidelines and quality gates

## Step 2: Review R Scripts

Read the pipeline scripts to understand data flow:
- `R/scrape_airports_navaids.R` - Main orchestrator (checks FAA, downloads, triggers pipeline)
- `R/clean_data.R` - Data transformation (filters, selects columns)
- `R/push_to_supabase.R` - Database upload (batch POST via REST API)

## Step 3: Git Status and History

```bash
echo "=== Branch ==="
git branch --show-current

echo ""
echo "=== Last 8 commits ==="
git log -8 --oneline

echo ""
echo "=== Uncommitted changes ==="
git status --short
```

## Step 4: Data Directory State

```bash
echo "=== Raw Data ==="
ls -la data/raw/ 2>/dev/null || echo "No raw data directories"

echo ""
echo "=== Clean Data ==="
ls -la data/clean/ 2>/dev/null || echo "No clean data files"

echo ""
echo "=== Data file sizes ==="
du -sh data/*/ 2>/dev/null || echo "No data subdirectories"
```

## Step 5: Generate Summary Report

Provide a structured summary:

### Project Context
- Current pipeline state (raw data date, clean data status)
- Recent activity (last commit, uncommitted changes)

### Pipeline Status
| Stage | Status | Details |
|-------|--------|---------|
| Raw Data | [Present/Missing] | Directory: data/raw/{date}_*_CSV/ |
| Clean Data | [Present/Missing] | Files: airports.csv, navaids.csv |
| Supabase | [Unknown] | Check via API or recent push logs |

### Blocking Issues
List any issues preventing pipeline execution:
- Missing .Renviron or API key
- Missing raw data
- Uncommitted changes that need attention

### Ready for Work
Confirm understanding of:
- Non-negotiables from CLAUDE.md
- Current coding standards (styler, lintr, testthat)
- Git commit format requirements