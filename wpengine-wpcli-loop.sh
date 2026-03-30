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
#   ./wpengine-wpcli-loop.sh [--dry-run] [--concurrency N] <sites_csv_file> <commands_csv_file>
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
CONCURRENCY=1

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --concurrency)
            if [[ $# -lt 2 || ! "${2:-}" =~ ^[0-9]+$ || "${2:-0}" -lt 1 ]]; then
                echo "Error: --concurrency requires a positive integer (example: --concurrency 4)"
                exit 1
            fi
            CONCURRENCY="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--concurrency N] <sites_csv_file> <commands_csv_file>"
            exit 0
            ;;
        -*)
            echo "Error: Unknown option '$1'"
            echo "Usage: $0 [--dry-run] [--concurrency N] <sites_csv_file> <commands_csv_file>"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# --- Usage check ---
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 [--dry-run] [--concurrency N] <sites_csv_file> <commands_csv_file>"
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
SSH_CONTROL_PATH="${TMPDIR:-/tmp}/wpe-tools-ssh-%C"
SSH_OPTS=(
    -T
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=15
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=3
    -o ControlMaster=auto
    -o ControlPersist=120
    -o ControlPath="$SSH_CONTROL_PATH"
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

read_site_stat() {
    local status_file="$1"
    local key
    local value
    local attempted=0
    local failed_cmds=0
    local site_failed=1

    while IFS='=' read -r key value; do
        case "$key" in
            attempted) attempted="$value" ;;
            failed_cmds) failed_cmds="$value" ;;
            site_failed) site_failed="$value" ;;
        esac
    done < "$status_file"

    TOTAL_COMMANDS=$((TOTAL_COMMANDS + attempted))
    FAILED_COMMANDS=$((FAILED_COMMANDS + failed_cmds))

    if [[ "$site_failed" == "1" ]]; then
        FAILED_SITES=$((FAILED_SITES + 1))
        OVERALL_FAILED=1
    else
        SUCCESSFUL_SITES=$((SUCCESSFUL_SITES + 1))
    fi
}

# --- Function to run WP-CLI commands on a single environment ---
run_wpcli() {
    local env="$1"
    local status_file="${2:-}"
    local host="${env}@${env}.ssh.wpengine.net"
    local site_failed=0
    local remote_cmd=""
    local cmd_b64=""
    local cmd_start_ts=0
    local cmd_end_ts=0
    local cmd_duration=0
    local attempted=0
    local failed_cmds=0

    echo "----------------------------------------"
    echo "[$(date '+%F %T')] Connecting to: $env ($host)"
    echo "----------------------------------------"

    if ! run_ssh_with_retry "$host" "cd \"/sites/${env}\" && command -v wp >/dev/null 2>&1"; then
        echo "❌ Preflight failed on $env (directory or WP-CLI check failed)"
        site_failed=1
        if [[ -n "$status_file" ]]; then
            printf "attempted=%s\nfailed_cmds=%s\nsite_failed=%s\n" "$attempted" "$failed_cmds" "$site_failed" > "$status_file"
        fi
        return 1
    fi

    for cmd in "${WPCLI_COMMANDS[@]}"; do
        attempted=$((attempted + 1))
        echo ">>> Running: $cmd"
        cmd_start_ts=$(date +%s)

        if (( DRY_RUN == 1 )); then
            echo "🧪 Dry run: command not executed"
            continue
        fi

        # Encode the command to avoid shell tokenization issues over SSH,
        # then decode and execute remotely inside the site directory.
        cmd_b64="$(printf '%s' "$cmd" | base64 | tr -d '\n')"
        printf -v remote_cmd \
            'cd "/sites/%s" && printf %%s %q | base64 --decode | bash' \
            "$env" \
            "$cmd_b64"
        if ! run_ssh_with_retry "$host" "$remote_cmd"; then
            echo "❌ Command failed: $cmd"
            failed_cmds=$((failed_cmds + 1))
            site_failed=1
        else
            cmd_end_ts=$(date +%s)
            cmd_duration=$((cmd_end_ts - cmd_start_ts))
            echo "⏱️ Completed in ${cmd_duration}s"
        fi
    done

    if (( site_failed == 1 )); then
        echo "⚠️ Finished with command failures: $env"
        if [[ -n "$status_file" ]]; then
            printf "attempted=%s\nfailed_cmds=%s\nsite_failed=%s\n" "$attempted" "$failed_cmds" "$site_failed" > "$status_file"
        fi
        return 1
    fi

    echo "✅ Finished: $env"
    echo
    if [[ -n "$status_file" ]]; then
        printf "attempted=%s\nfailed_cmds=%s\nsite_failed=%s\n" "$attempted" "$failed_cmds" "$site_failed" > "$status_file"
    fi
}

# --- Loop through environments with optional concurrency ---
declare -a RUN_PIDS=()
declare -a RUN_STATUS_FILES=()

for env in "${ENVS[@]}"; do
    TOTAL_SITES=$((TOTAL_SITES + 1))

    if [[ ! "$env" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
        FAILED_SITES=$((FAILED_SITES + 1))
        OVERALL_FAILED=1
        log_line "❌ Invalid environment name '$env' (allowed: letters, numbers, hyphens)"
        continue
    fi

    status_file="$(mktemp)"

    if (( CONCURRENCY <= 1 )); then
        if ! run_wpcli "$env" "$status_file"; then
            log_line "❌ Error running commands on $env — continuing to next site"
        fi
        read_site_stat "$status_file"
        rm -f "$status_file"
    else
        run_wpcli "$env" "$status_file" &
        RUN_PIDS+=("$!")
        RUN_STATUS_FILES+=("$status_file")

        if (( ${#RUN_PIDS[@]} >= CONCURRENCY )); then
            if ! wait "${RUN_PIDS[0]}"; then
                true
            fi
            read_site_stat "${RUN_STATUS_FILES[0]}"
            rm -f "${RUN_STATUS_FILES[0]}"
            RUN_PIDS=("${RUN_PIDS[@]:1}")
            RUN_STATUS_FILES=("${RUN_STATUS_FILES[@]:1}")
        fi
    fi
done

for i in "${!RUN_PIDS[@]}"; do
    if ! wait "${RUN_PIDS[$i]}"; then
        true
    fi
    read_site_stat "${RUN_STATUS_FILES[$i]}"
    rm -f "${RUN_STATUS_FILES[$i]}"
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
