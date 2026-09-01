#!/usr/bin/env bash
# Compact test report from an .xcresult bundle, for GitHub Step Summary.
#
# Design goal: agents and humans read failures WITHOUT downloading the
# (potentially large) .xcresult artifact:
#   - stdout: small markdown (counts, failed tests + messages, slowest tests)
#   - stderr: `::error` workflow annotations for failed tests (surfaces on the
#     PR checks UI; capped at 10, GitHub's per-step limit)
#
# Usage: test-failure-report.sh <path-to-xcresult> <title>
# Always exits 0 — report generation must never fail the job.

set -uo pipefail

xcresult="${1:?usage: test-failure-report.sh <xcresult> <title>}"
title="${2:-Tests}"

emit() { printf '%s\n' "$*"; }

emit "### $title"
emit ""

if [ ! -d "$xcresult" ]; then
    emit "> ⚠️ Result bundle \`$xcresult\` not found — the failure happened before tests ran (build/config error). Read the xcodebuild log above."
    exit 0
fi

summary=$(xcrun xcresulttool get test-results summary --path "$xcresult" --compact 2>/dev/null || true)
tests=$(xcrun xcresulttool get test-results tests --path "$xcresult" --compact 2>/dev/null || true)

if [ -z "$summary" ]; then
    emit "> ⚠️ Could not read \`$xcresult\` (corrupt or xcresulttool incompatible). Read the xcodebuild log above."
    exit 0
fi

# Overview: counts + wall duration (seconds, rounded)
echo "$summary" | jq -r \
    '"\(if .failedTests > 0 then "❌" else "✅" end) **\(.passedTests) passed / \(.failedTests) failed / \(.skippedTests) skipped** · total \((((.finishTime // .startTime) - .startTime) * 10 | round / 10))s"' \
    || true

# Failed tests with failure messages (message truncated to keep the summary light)
if [ -n "$tests" ]; then
    failed_md=$(echo "$tests" | jq -r '
        def msgs: [.children // [] | .[]? | select(.nodeType? == "Failure Message") | .name] | join("\n") | .[0:1200];
        [.. | objects | select(.nodeType? == "Test Case" and .result? == "Failed")]
        | if length == 0 then empty
          else "#### Failed tests", "",
               (map("#### ✗ \(.name) (\(.duration // "?"))\n\n```text\n\(msgs | if length > 0 then . else "(no failure message captured — read the raw xcodebuild log)" end)\n```") | join("\n\n"))
          end' 2>/dev/null || true)
    if [ -n "$failed_md" ]; then
        emit "$failed_md"
        emit ""
    fi
fi

# Slowest tests (pass or fail) — keeps runtime regressions visible
if [ -n "$tests" ]; then
    slowest=$(echo "$tests" | jq -r '
        [.. | objects | select(.nodeType? == "Test Case")]
        | if length == 0 then empty
          else sort_by((.duration // "0s") | sub("s$";"") | tonumber? // 0) | reverse | .[:10]
          | "#### Slowest tests", "", "| test | duration | result |", "|---|---:|---|",
            (map("| \(.name) | \(.duration // "?") | \(.result // "?") |") | join("\n"))
          end' 2>/dev/null || true)
    if [ -n "$slowest" ]; then
        emit "$slowest"
        emit ""
    fi
fi

# Workflow annotations for failed tests (stderr, cap 10)
if [ -n "$tests" ]; then
    echo "$tests" | jq -r '
        def msgs: [.children // [] | .[]? | select(.nodeType? == "Failure Message") | .name] | join(" | ") | gsub("[\r\n]"; " ") | .[0:240];
        [.. | objects | select(.nodeType? == "Test Case" and .result? == "Failed")][0:10][]
        | "::error title=\(.name)::\(msgs | if length > 0 then . else "failed (no message captured)" end)"' >&2 2>/dev/null || true
fi

exit 0
