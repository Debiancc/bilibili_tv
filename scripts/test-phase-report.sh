# Emit the per-phase duration markdown table shared by the unit and UI test
# jobs (Boot non-blocking -> build-for-testing -> wait-ready ->
# test-without-building). Print to stdout; the caller mirrors it into
# $GITHUB_STEP_SUMMARY and the job log.
#
# Usage: test-phase-report.sh "<label>" <PREFIX> <raw-test-log>
#   e.g.  test-phase-report.sh "UI tests" UI raw-ui.log
# Env: <PREFIX>_BUILD_SECONDS, <PREFIX>_BOOT_SECONDS, <PREFIX>_BOOT_WALL_SECONDS,
#      <PREFIX>_RUN_SECONDS, <PREFIX>_RUN_START_TS, <PREFIX>_RUN_END_TS,
#      <PREFIX>_SIM_UDID (all optional; phases never reached report 0 / n/a).
#
# No `set -e`: the session-window grep legitimately misses on failed/incomplete
# logs and must degrade to n/a instead of aborting the report.

LABEL="$1"
P="$2"
RAW_LOG="$3"

indirect() { local name="${P}_$1"; printf '%s' "${!name:-}"; }

BUILD_SECONDS=$(indirect BUILD_SECONDS); BUILD_SECONDS=${BUILD_SECONDS:-0}
BOOT_SECONDS=$(indirect BOOT_SECONDS); BOOT_SECONDS=${BOOT_SECONDS:-0}
BOOT_WALL_SECONDS=$(indirect BOOT_WALL_SECONDS); BOOT_WALL_SECONDS=${BOOT_WALL_SECONDS:-0}
RUN_SECONDS=$(indirect RUN_SECONDS); RUN_SECONDS=${RUN_SECONDS:-0}
RUN_START_TS=$(indirect RUN_START_TS)
RUN_END_TS=$(indirect RUN_END_TS)
SIM_UDID=$(indirect SIM_UDID)

fmt() { printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); }
opt() { if [ -n "$1" ]; then fmt "$1"; else echo "n/a"; fi; }
to_epoch() { date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s 2>/dev/null || echo 0; }

# App-install window inside the test phase: xcodebuild's console output never
# marks "Installing", so query the simulator unified log — first
# installcoordination event naming our bundle through the last `setComplete:`.
# The sim installs nothing else in this window (booted in a previous step), and
# both the log timestamps and --start/--end are host-local (UTC on CI runners).
INSTALL_SECONDS=""
if [ -n "$SIM_UDID" ] && [ -n "$RUN_START_TS" ] && [ -n "$RUN_END_TS" ]; then
  install_log=$(xcrun simctl spawn "$SIM_UDID" log show \
    --style compact --start "$RUN_START_TS" --end "$RUN_END_TS" \
    --predicate 'subsystem == "com.apple.installcoordination"' 2>/dev/null || true)
  i_first=$(echo "$install_log" | grep -m1 "bilibili" | cut -c1-19)
  i_last=$(echo "$install_log" | grep "setComplete:" | tail -1 | cut -c1-19)
  if [ -n "$i_first" ] && [ -n "$i_last" ]; then
    INSTALL_SECONDS=$(( $(to_epoch "$i_last") - $(to_epoch "$i_first") ))
  fi
fi

# Test-session window straight from the log's own timestamps
# (`Test Suite 'All tests' started/passed at ...`); the remainder of the test
# phase is launch + teardown overhead.
SESSION_SECONDS=""
s0=$(grep -m1 "Test Suite 'All tests' started at" "$RAW_LOG" | sed -E 's/.*started at ([0-9-]+ [0-9:]+)\..*/\1/')
s1=$(grep -E "Test Suite 'All tests' (passed|failed) at" "$RAW_LOG" | tail -1 | sed -E 's/.*at ([0-9-]+ [0-9:]+)\..*/\1/')
if [ -n "$s0" ] && [ -n "$s1" ]; then
  SESSION_SECONDS=$(( $(to_epoch "$s1") - $(to_epoch "$s0") ))
fi

total=$((BUILD_SECONDS + BOOT_SECONDS + RUN_SECONDS))
{
  echo ""
  echo "### Phase durations"
  echo ""
  echo "| Phase | Duration |"
  echo "|---|---:|"
  echo "| Build for testing | $(fmt "$BUILD_SECONDS") |"
  echo "| Simulator boot (overlaps build) | $(fmt "$BOOT_WALL_SECONDS") |"
  echo "| ↳ boot wait reaped after build | $(fmt "$BOOT_SECONDS") |"
  echo "| Test execution | $(fmt "$RUN_SECONDS") |"
  echo "| ↳ app install (sim log) | $(opt "$INSTALL_SECONDS") |"
  echo "| ↳ test session (first→last suite) | $(opt "$SESSION_SECONDS") |"
  echo "| **Total (wall: build + boot-wait + test)** | **$(fmt "$total")** |"
}
