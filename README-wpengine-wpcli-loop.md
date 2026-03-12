# WP Engine WP-CLI Loop

Run the same WP-CLI command list across multiple WP Engine installs over SSH.

> This repository is **not** a DDEV project. Run commands directly in your local shell.

---

## What This Script Does

`wpengine-wpcli-loop.sh`:

1. Reads a **sites file** (one install name per line)
2. Reads a **commands file** (one WP-CLI command per line)
3. Connects to each site as `<install>@<install>.ssh.wpengine.net`
4. Runs commands in `/sites/<install>` in order
5. Writes all output to terminal and a timestamped log file

If one site fails, the script keeps going to the next site.

---

## Quick Start (First Run)

### 1) Create a small sites file

```csv
# test one site first
myinstallstaging
```

### 2) Create a safe commands file

```csv
wp plugin list
```

### 3) Dry-run first

```bash
./wpengine-wpcli-loop.sh --dry-run sites.csv commands.csv
```

### 4) Execute for real

```bash
./wpengine-wpcli-loop.sh sites.csv commands.csv
```

---

## Requirements

- SSH access to your WP Engine installs (SSH key added in WP Engine portal)
- Bash 4+ on your local machine
- WP-CLI available on the WP Engine SSH environment

---

## File Formats

### Sites file (`sites.csv`)

One install/environment name per line:

```csv
# Production
myinstall
# Staging
myinstallstaging
# Dev
myinstalldev
```

### Commands file (`commands.csv`)

One WP-CLI command per line:

```csv
# Update stack
wp plugin update --all
wp theme update --all
wp core update
wp core update-db
wp cache flush
```

### Parsing rules (both files)

- Blank lines are ignored
- Lines starting with `#` are ignored
- Leading/trailing whitespace is trimmed
- BOM and CRLF are normalized automatically

---

## Usage

```bash
./wpengine-wpcli-loop.sh [--dry-run] <sites_file> <commands_file>
```

### Examples

```bash
./wpengine-wpcli-loop.sh sites.csv plugins-themes-update.csv
./wpengine-wpcli-loop.sh newfrontierweb.csv core-update.csv
./wpengine-wpcli-loop.sh --dry-run sites.csv plugins-themes-update.csv
```

### Arguments

- `<sites_file>`: path to install list file
- `<commands_file>`: path to WP-CLI command list file
- `--dry-run`: validates connection and previews commands without executing WP-CLI commands

---

## Output and Logs

Each run creates:

- `./wpcli_run_YYYY-MM-DD_HH-MM-SS.log`

The log includes:

- connection/preflight checks
- each command attempted
- command failures
- final summary (sites/commands success and failure counts)

---

## Failure Behavior (Important)

- Missing sites/commands file: script exits with error
- Site preflight fails (SSH, directory, or `wp` not found): site is marked failed, script continues
- A command fails on a site: command is marked failed, remaining commands continue
- Final exit code is non-zero if any site or command failed
- SSH operations retry once automatically on failure

---

## Safety Tips

- Start with one staging/dev site before production
- Use `--dry-run` before destructive actions
- Keep production and non-production in separate site files
- Keep command files focused (one task per file)
- Review the generated log before running the next batch

---

## Common Problems

### `Permission denied (publickey)`

Your local SSH key is not authorized for that WP Engine install.

### `WP-CLI not found on remote server`

Preflight failed to detect `wp` in that environment. Verify WP Engine SSH environment and path.

### `Directory /sites/<install> not found`

The install name in the sites file is incorrect for that environment.

---

## Included Example Files

- `sites.csv`: sample list of installs
- `sample-sites.csv`: starter sites template for new users
- `sample-commands.csv`: starter safe command template for new users
- `plugins-themes-update.csv`: plugin/theme/core maintenance commands
- `core-update.csv`: core and DB update commands
- `delete-disable-comments.csv`: comment-closing commands
