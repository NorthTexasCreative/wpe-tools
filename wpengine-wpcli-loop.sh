#!/usr/bin/env bash
#
# wpengine-wpcli-loop.sh — Run WP-CLI commands on multiple WP Engine sites via SSH
#
# Overview:
#   Connects to each WP Engine environment listed in a sites CSV file and runs
#   a set of WP-CLI commands from a commands CSV file. Output is printed to
#   the terminal and appended to a timestamped log file.
#
# Usage:
#   ./wpengine-wpcli-loop.sh [--dry-run] <sites_csv_file> <commands_csv_file>
#
# Arguments:
#   sites_csv_file   — Path to a CSV with one WP Engine install name per line
#                       (e.g. myinstall, myinstalldev). Blank lines and lines
#                       starting with # are ignored. Case-insensitive filename.
#   commands_csv_file — Path to a CSV with one WP-CLI command per line
#                        (e.g. wp plugin list, wp theme update --all).
#                        Blank lines and # comments are ignored.
#
# Requirements:
#   - SSH access to WP Engine (SSH key configured for <install>@<install>.ssh.wpengine.net)
#   - Bash 4+ (for mapfile)
#
# Output:
#   Log file: ./wpcli_run_YYYY-MM-DD_HH-MM-SS.log
#
# Example:
#   ./wpengine-wpcli-loop.sh sites.csv plugins-themes-update.csv
#
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    shift
fi

# --- Usage check ---
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 [--dry-run] <sites_csv_file> <commands_csv_file>"
    echo "Example: $0 my-sites.csv update-plugins.csv"
    exit 1
fi

SITES_FILE="$1"
CMD_FILE="$2"

# --- Function to find CSV file ignoring case/BOM/CRLF ---
find_csv_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        echo "$file"
        return
    fi
    local match
    match=$(find . -maxdepth 1 -type f -iname "$file" -print -quit)
    if [[ -n "$match" ]]; then
        echo "${match#./}"
    else
        echo ""
    fi
}

# --- Locate sites CSV ---
SITES_FILE=$(find_csv_file "$SITES_FILE")
if [[ -z "$SITES_FILE" ]]; then
    echo "Error: Sites CSV file '$1' not found in $(pwd)"
    exit 1
fi
echo "✅ Using sites CSV: $SITES_FILE"

# --- Locate commands CSV ---
CMD_FILE=$(find_csv_file "$CMD_FILE")
if [[ -z "$CMD_FILE" ]]; then
    echo "Error: Commands CSV file '$2' not found in $(pwd)"
    exit 1
fi
echo "✅ Using commands CSV: $CMD_FILE"

# --- Read sites ---
mapfile -t ENVS < <(
    sed '1s/^\xEF\xBB\xBF//' "$SITES_FILE" | \
    tr -d '\r' | \
    awk 'NF && $1 !~ /^#/' | \
    sed 's/^[ \t]*//;s/[ \t]*$//'
)

# --- Read commands ---
mapfile -t WPCLI_COMMANDS < <(
    sed '1s/^\xEF\xBB\xBF//' "$CMD_FILE" | \
    tr -d '\r' | \
    awk 'NF && $1 !~ /^#/' | \
    sed 's/^[ \t]*//;s/[ \t]*$//'
)

if [[ ${#ENVS[@]} -eq 0 ]]; then
    echo "Error: No environments found in $SITES_FILE"
    exit 1
fi
if [[ ${#WPCLI_COMMANDS[@]} -eq 0 ]]; then
    echo "Error: No commands found in $CMD_FILE"
    exit 1
fi

LOG_FILE="./wpcli_run_$(date +%F_%H-%M-%S).log"
SSH_OPTS=(
    -T
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=15
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=3
)

TOTAL_SITES=0
SUCCESSFUL_SITES=0
FAILED_SITES=0
TOTAL_COMMANDS=0
FAILED_COMMANDS=0
OVERALL_FAILED=0

log_line() {
    echo "$1"
}

# Mirror all output to both terminal and log file.
exec > >(tee -a "$LOG_FILE") 2>&1

run_ssh_with_retry() {
    local host="$1"
    local remote_cmd="$2"
    local attempts=2
    local attempt

    for (( attempt=1; attempt<=attempts; attempt++ )); do
        if ssh "${SSH_OPTS[@]}" "$host" "$remote_cmd"; then
            return 0
        fi

        if (( attempt < attempts )); then
            log_line "⚠️ SSH command failed for $host (attempt $attempt/$attempts), retrying..."
            sleep 2
        fi
    done

    return 1
}

# --- Function to run WP-CLI commands on a single environment ---
run_wpcli() {
    local env="$1"
    local host="${env}@${env}.ssh.wpengine.net"
    local site_failed=0

    echo "----------------------------------------"
    echo "[$(date '+%F %T')] Connecting to: $env ($host)"
    echo "----------------------------------------"

    if ! run_ssh_with_retry "$host" "cd \"/sites/${env}\" && command -v wp >/dev/null 2>&1"; then
        echo "❌ Preflight failed on $env (directory or WP-CLI check failed)"
        return 1
    fi

    for cmd in "${WPCLI_COMMANDS[@]}"; do
        TOTAL_COMMANDS=$((TOTAL_COMMANDS + 1))
        echo ">>> Running: $cmd"

        if (( DRY_RUN == 1 )); then
            echo "🧪 Dry run: command not executed"
            continue
        fi

        if ! run_ssh_with_retry "$host" "cd \"/sites/${env}\" && bash -lc $(printf '%q' "$cmd")"; then
            echo "❌ Command failed: $cmd"
            FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
            site_failed=1
        fi
    done

    if (( site_failed == 1 )); then
        echo "⚠️ Finished with command failures: $env"
        return 1
    fi

    echo "✅ Finished: $env"
    echo
}

# --- Loop through environments with error handling ---
for env in "${ENVS[@]}"; do
    TOTAL_SITES=$((TOTAL_SITES + 1))

    if [[ ! "$env" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
        FAILED_SITES=$((FAILED_SITES + 1))
        OVERALL_FAILED=1
        log_line "❌ Invalid environment name '$env' (allowed: letters, numbers, hyphens)"
        continue
    fi

    if ! run_wpcli "$env"; then
        FAILED_SITES=$((FAILED_SITES + 1))
        OVERALL_FAILED=1
        log_line "❌ Error running commands on $env — continuing to next site"
    else
        SUCCESSFUL_SITES=$((SUCCESSFUL_SITES + 1))
    fi
done

log_line "Run summary:"
log_line "  Sites total: $TOTAL_SITES"
log_line "  Sites successful: $SUCCESSFUL_SITES"
log_line "  Sites failed: $FAILED_SITES"
log_line "  Commands attempted: $TOTAL_COMMANDS"
log_line "  Commands failed: $FAILED_COMMANDS"
log_line "All tasks completed. Log saved to: $LOG_FILE"

if (( OVERALL_FAILED == 1 )); then
    exit 1
fi
