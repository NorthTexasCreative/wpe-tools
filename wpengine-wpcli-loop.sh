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
#   ./wpengine-wpcli-loop.sh <sites_csv_file> <commands_csv_file>
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

# --- Usage check ---
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <sites_csv_file> <commands_csv_file>"
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

# --- Function to run WP-CLI commands on a single environment ---
run_wpcli() {
    local env="$1"
    local host="${env}@${env}.ssh.wpengine.net"

    {
        echo "----------------------------------------"
        echo "[$(date '+%F %T')] Connecting to: $env ($host)"
        echo "----------------------------------------"

        ssh -T "$host" bash <<EOF
            set -e
            cd "/sites/${env}" || { echo "Error: Directory /sites/${env} not found"; exit 1; }

            if ! command -v wp >/dev/null 2>&1; then
                echo "Error: WP-CLI not found on remote server."
                exit 1
            fi

$(for cmd in "${WPCLI_COMMANDS[@]}"; do
    echo "            echo '>>> Running: $cmd'"
    echo "            $cmd || echo '❌ Command failed: $cmd'"
done)
EOF

        echo "✅ Finished: $env"
        echo
    } | tee -a "$LOG_FILE"
}

# --- Loop through environments with error handling ---
for env in "${ENVS[@]}"; do
    if ! run_wpcli "$env"; then
        echo "❌ Error running commands on $env — continuing to next site" | tee -a "$LOG_FILE"
    fi
done

echo "All tasks completed. Log saved to: $LOG_FILE"
