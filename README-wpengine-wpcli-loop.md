# wpengine-wpcli-loop.sh

Run WP-CLI commands on multiple WP Engine sites over SSH from CSV-driven site and command lists.

## Overview

The script:

1. Reads a **sites CSV** — one WP Engine install/environment name per line (e.g. `myinstall`, `myinstalldev`).
2. Reads a **commands CSV** — one WP-CLI command per line (e.g. `wp plugin list`, `wp theme update --all`).
3. For each site, SSHes to `<install>@<install>.ssh.wpengine.net`, `cd`s to `/sites/<install>`, and runs each command in order.
4. Prints all output to the terminal and appends it to a timestamped log file: `./wpcli_run_YYYY-MM-DD_HH-MM-SS.log`.

If a site or command fails, the script logs the error and continues with the next site. Commands run in the context of the site’s install directory on WP Engine.

## Requirements

- **SSH access to WP Engine** — Your SSH key must be configured for WP Engine (e.g. in the WP Engine User Portal). You connect as `<install>@<install>.ssh.wpengine.net`.
- **Bash 4+** — The script uses `mapfile`; typical Linux/macOS bash meets this.
- **WP-CLI on WP Engine** — WP Engine provides WP-CLI in the SSH environment; the script checks for it and exits with an error if it’s missing.

## How to Use

### 1. Create a sites CSV

One WP Engine install name per line. These are the “install names” you use in the WP Engine dashboard and SSH (e.g. `myinstall`, `myinstalldev`, `myinstallstaging`).

- Blank lines and lines starting with `#` are ignored.
- Leading/trailing spaces are trimmed.
- File can have a BOM or CRLF line endings; the script normalizes them.

**Example `sites.csv`:**

```csv
# Production
myinstall
# Staging
myinstallstaging
# Dev
myinstalldev
```

### 2. Create a commands CSV

One WP-CLI command per line. Commands are run in order inside `/sites/<install>` on the server.

- Blank lines and lines starting with `#` are ignored.
- Leading/trailing spaces are trimmed.
- Same BOM/CRLF handling as the sites file.

**Example `plugins-themes-update.csv`:**

```csv
# Update plugins and themes
wp plugin update --all
wp theme update --all
wp core update
```

**Example `core-update.csv`:**

```csv
wp core update
wp core update-db
```

### 3. Run the script

From the directory that contains (or can see) your CSV files:

```bash
./wpengine-wpcli-loop.sh <sites_csv_file> <commands_csv_file>
```

**Examples:**

```bash
./wpengine-wpcli-loop.sh sites.csv plugins-themes-update.csv
./wpengine-wpcli-loop.sh newfrontierweb.csv core-update.csv
./wpengine-wpcli-loop.sh my-sites.csv update-plugins.csv
```

- **Sites file:** path to the CSV of WP Engine install names.
- **Commands file:** path to the CSV of WP-CLI commands.

Filenames are matched **case-insensitively** (e.g. `Sites.CSV` will find `sites.csv` in the current directory).

### 4. Check the log

After each run, a log file is written in the current directory:

- **Name:** `wpcli_run_YYYY-MM-DD_HH-MM-SS.log`
- **Contents:** Full SSH output for each site (connection, commands, errors).

Use this to verify what ran and to debug failures.

## CSV file location

- CSV paths can be relative or absolute.
- If the script doesn’t find the file as given, it looks in the **current directory** for a file with the same name (case-insensitive). So `./wpengine-wpcli-loop.sh sites.csv commands.csv` will use `./sites.csv` and `./commands.csv` when run from the script’s directory.

## Error handling

- **Missing CSV or no sites/commands:** The script exits with an error and usage message.
- **SSH or directory failure for a site:** The failure is logged; the script continues with the next site.
- **WP-CLI command failure on a site:** The failed command is reported; the script continues with the next command and then the next site.

## Tips

- Test with a single site and one or two safe commands (e.g. `wp plugin list`) before running updates on many sites.
- Use comment lines (`#`) in your CSVs to document which sites or commands you’re running.
- Keep a backup or use staging/dev installs when running destructive or bulk update commands.
