#!/usr/bin/env bash
# ==============================================================================
# Alicia Desktop Environment - Test Runner
# Proyecto Tomorrow - Enterprise Linux Desktop for Android
#
# Runs all test suites, collects results, generates a summary report,
# and returns an appropriate exit code.
#
# Usage:
#   ./run-all-tests.sh              # Run all tests
#   ./run-all-tests.sh --verbose    # Verbose output
#   ./run-all-tests.sh --suite core # Run only the core test suite
#   ./run-all-tests.sh --list       # List available test suites
# ==============================================================================

set -uo pipefail

# ---- Constants ----
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly RESULTS_DIR="${SCRIPT_DIR}/results"
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly REPORT_FILE="${RESULTS_DIR}/report_${TIMESTAMP}.txt"

# ---- Colors ----
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_MAGENTA='\033[0;35m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_RESET='\033[0m'

# ---- Available Test Suites ----
declare -A TEST_SUITES=(
    ["core"]="test-core.sh"
    ["system"]="test-system.sh"
    ["installation"]="test-installation.sh"
)

# ---- Global Results ----
declare -A SUITE_PASSED=()
declare -A SUITE_FAILED=()
declare -A SUITE_TOTAL=()
declare -A SUITE_STATUS=()
declare -A SUITE_DURATION=()

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_RUN=0
OVERALL_EXIT=0

# ---- Command Line Parsing ----
VERBOSE=false
SELECTED_SUITES=()
LIST_ONLY=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --verbose, -v    Enable verbose output"
    echo "  --suite NAME     Run only the specified test suite (can be repeated)"
    echo "  --list, -l       List available test suites and exit"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "Available suites: ${!TEST_SUITES[*]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --suite)
            if [[ -z "${2:-}" ]]; then
                echo -e "${C_RED}Error: --suite requires a suite name${C_RESET}" >&2
                exit 1
            fi
            SELECTED_SUITES+=("$2")
            shift 2
            ;;
        --list|-l)
            LIST_ONLY=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${C_RED}Error: Unknown option: $1${C_RESET}" >&2
            usage
            exit 1
            ;;
    esac
done

# ---- List Suites ----
if [[ "$LIST_ONLY" == true ]]; then
    echo -e "${C_BOLD}Available test suites:${C_RESET}"
    for suite in "${!TEST_SUITES[@]}"; do
        local_file="${SCRIPT_DIR}/${TEST_SUITES[$suite]}"
        status="✓"
        [[ -f "$local_file" ]] || status="✗ (missing)"
        printf "  %-15s %s  %s\n" "$suite" "$status" "${TEST_SUITES[$suite]}"
    done
    exit 0
fi

# ---- Determine Which Suites to Run ----
SUITES_TO_RUN=()
if [[ ${#SELECTED_SUITES[@]} -gt 0 ]]; then
    for s in "${SELECTED_SUITES[@]}"; do
        if [[ -n "${TEST_SUITES[$s]:-}" ]]; then
            SUITES_TO_RUN+=("$s")
        else
            echo -e "${C_RED}Error: Unknown suite '$s'${C_RESET}" >&2
            echo -e "Available suites: ${!TEST_SUITES[*]}" >&2
            exit 1
        fi
    done
else
    # Run all suites in order
    SUITES_TO_RUN=("core" "system" "installation")
fi

# ---- Prepare Results Directory ----
mkdir -p "${RESULTS_DIR}"

# ---- Banner ----
echo -e "${C_BOLD}${C_CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Alicia Desktop Environment - Test Runner          ║"
echo "║              Proyecto Tomorrow                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${C_RESET}"
echo -e "  Timestamp : ${C_BOLD}${TIMESTAMP}${C_RESET}"
echo -e "  Project   : ${C_DIM}${PROJECT_DIR}${C_RESET}"
echo -e "  Verbose   : ${VERBOSE}"
echo -e "  Suites    : ${C_BOLD}${SUITES_TO_RUN[*]}${C_RESET}"
echo ""

# ---- Functions ----

# Parse test output for pass/fail counts
parse_results() {
    local output="$1" suite="$2"

    # Strip ANSI escape codes for reliable parsing
    local clean_output
    clean_output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

    # Try to extract "Passed:  N" and "Failed:  N" from summary
    local passed failed total

    passed=$(echo "$clean_output" | grep -oP 'Passed:\s*\K[0-9]+' | tail -1)
    failed=$(echo "$clean_output" | grep -oP 'Failed:\s*\K[0-9]+' | tail -1)
    total=$(echo "$clean_output" | grep -oP 'Total:\s*\K[0-9]+' | tail -1)

    # Default to 0 if empty
    passed=${passed:-0}
    failed=${failed:-0}
    total=${total:-0}

    # Fallback: count PASS/FAIL lines if summary not found
    if [[ "$total" -eq 0 ]]; then
        passed=$(echo "$clean_output" | grep -c "PASS" || true)
        failed=$(echo "$clean_output" | grep -c "FAIL" || true)
        passed=${passed:-0}
        failed=${failed:-0}
        total=$((passed + failed))
    fi

    SUITE_PASSED[$suite]=$passed
    SUITE_FAILED[$suite]=$failed
    SUITE_TOTAL[$suite]=$total
}

# Run a single test suite
run_suite() {
    local suite="$1"
    local script="${TEST_SUITES[$suite]}"
    local script_path="${SCRIPT_DIR}/${script}"

    echo -e "${C_BOLD}${C_BLUE}┌─────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}│ Running: ${suite} (${script})${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}└─────────────────────────────────────────────────${C_RESET}"

    if [[ ! -f "$script_path" ]]; then
        echo -e "  ${C_RED}✗ Test script not found: $script_path${C_RESET}"
        SUITE_STATUS[$suite]="missing"
        SUITE_PASSED[$suite]=0
        SUITE_FAILED[$suite]=0
        SUITE_TOTAL[$suite]=0
        SUITE_DURATION[$suite]=0
        OVERALL_EXIT=1
        return
    fi

    if [[ ! -x "$script_path" ]]; then
        chmod +x "$script_path"
    fi

    # Run the suite and capture output
    local start_time end_time duration output exit_code

    start_time=$(date +%s)

    if [[ "$VERBOSE" == true ]]; then
        # Stream output directly
        output=$("$script_path" 2>&1 | tee /dev/stderr) || true
        exit_code=$?
    else
        # Capture output, show only on failure
        output=$("$script_path" 2>&1) || true
        exit_code=$?
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    SUITE_DURATION[$suite]=$duration

    # Save output to results
    echo "$output" > "${RESULTS_DIR}/${suite}_${TIMESTAMP}.log"

    # Parse results from output
    parse_results "$output" "$suite"

    # Determine status
    if [[ "${SUITE_FAILED[$suite]}" -eq 0 ]]; then
        SUITE_STATUS[$suite]="passed"
        echo -e "  ${C_GREEN}✓ PASSED${C_RESET} in ${duration}s (${SUITE_PASSED[$suite]} tests)"
    else
        SUITE_STATUS[$suite]="failed"
        echo -e "  ${C_RED}✗ FAILED${C_RESET} in ${duration}s (${SUITE_FAILED[$suite]} failures)"
        OVERALL_EXIT=1
        # Show failed test details
        local failed_lines
        failed_lines=$(echo "$output" | grep "FAIL" | head -10)
        if [[ -n "$failed_lines" ]]; then
            echo -e "  ${C_DIM}Failed tests:${C_RESET}"
            echo "$failed_lines" | while IFS= read -r line; do
                echo -e "    ${C_RED}${line}${C_RESET}"
            done
        fi
    fi

    echo ""
}

# ---- Run All Suites ----
for suite in "${SUITES_TO_RUN[@]}"; do
    run_suite "$suite"
done

# ---- Generate Report ----

echo -e "${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║                    Test Results Summary                     ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
echo ""

# Per-suite results
printf "  ${C_BOLD}%-15s %-10s %-10s %-10s %-10s %-10s${C_RESET}\n" \
    "Suite" "Status" "Passed" "Failed" "Total" "Time"
printf "  %-15s %-10s %-10s %-10s %-10s %-10s\n" \
    "─────" "──────" "──────" "──────" "─────" "────"

for suite in "${SUITES_TO_RUN[@]}"; do
    local_status="${SUITE_STATUS[$suite]:-unknown}"
    local_passed="${SUITE_PASSED[$suite]:-0}"
    local_failed="${SUITE_FAILED[$suite]:-0}"
    local_total="${SUITE_TOTAL[$suite]:-0}"
    local_duration="${SUITE_DURATION[$suite]:-0}s"

    # Color the status
    case "$local_status" in
        passed)  status_display="${C_GREEN}PASSED${C_RESET}" ;;
        failed)  status_display="${C_RED}FAILED${C_RESET}" ;;
        missing) status_display="${C_YELLOW}MISSING${C_RESET}" ;;
        *)       status_display="${C_DIM}UNKNOWN${C_RESET}" ;;
    esac

    printf "  %-15s " "$suite"
    echo -e -n "$status_display"
    printf " %-10s %-10s %-10s %-10s\n" "$local_passed" "$local_failed" "$local_total" "$local_duration"

    TOTAL_PASSED=$((TOTAL_PASSED + local_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + local_failed))
    TOTAL_RUN=$((TOTAL_RUN + local_total))
done

echo ""
echo -e "  ${C_BOLD}─────────────────────────────────────────────${C_RESET}"
echo -e "  ${C_BOLD}Total:${C_RESET}   ${TOTAL_RUN}"
echo -e "  ${C_BOLD}Passed:${C_RESET}  ${C_GREEN}${TOTAL_PASSED}${C_RESET}"
echo -e "  ${C_BOLD}Failed:${C_RESET}  ${C_RED}${TOTAL_FAILED}${C_RESET}"

# Calculate pass rate
if [[ $TOTAL_RUN -gt 0 ]]; then
    pass_rate=$((TOTAL_PASSED * 100 / TOTAL_RUN))
    echo -e "  ${C_BOLD}Rate:${C_RESET}    ${pass_rate}%"
fi

echo ""

# ---- Write Report File ----
{
    echo "Alicia Desktop Environment - Test Report"
    echo "Timestamp: ${TIMESTAMP}"
    echo "Project: ${PROJECT_DIR}"
    echo ""
    echo "Suite Results:"
    for suite in "${SUITES_TO_RUN[@]}"; do
        echo "  ${suite}: status=${SUITE_STATUS[$suite]:-unknown} passed=${SUITE_PASSED[$suite]:-0} failed=${SUITE_FAILED[$suite]:-0} total=${SUITE_TOTAL[$suite]:-0} duration=${SUITE_DURATION[$suite]:-0}s"
    done
    echo ""
    echo "Totals: run=${TOTAL_RUN} passed=${TOTAL_PASSED} failed=${TOTAL_FAILED}"
    echo "Exit Code: ${OVERALL_EXIT}"
} > "$REPORT_FILE"

echo -e "  ${C_DIM}Report saved to: ${REPORT_FILE}${C_RESET}"
echo ""

# ---- Final Status ----
if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "${C_GREEN}${C_BOLD}  ✓ All tests passed!${C_RESET}"
    echo ""
    exit 0
else
    echo -e "${C_RED}${C_BOLD}  ✗ ${TOTAL_FAILED} test(s) failed!${C_RESET}"
    echo ""
    exit 1
fi
