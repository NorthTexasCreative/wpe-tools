# WP Engine WP-CLI Loop

Run the same WP-CLI command list across multiple WP Engine installs over SSH.

> This repository is **not** a DDEV project. Run commands directly in your local shell.

## What This Tool Does

This is a shell script runner, not a WordPress plugin.

- It loops through a list of WP Engine install names
- It runs one or more WP-CLI commands on each install over SSH
- It writes full output to terminal and a timestamped log file
- It continues to the next site when one site fails

## WP Engine Key Setup (Do This First)

1. Generate an SSH key pair if you do not have one:

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

2. Copy your public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

3. In WP Engine User Portal:
   - open your profile/user settings
   - add the copied public key to SSH keys
   - confirm your user has access to the installs in your sites file

4. Verify SSH access to one install:

```bash
ssh <install>@<install>.ssh.wpengine.net
```

If this SSH test fails, fix key or access issues before running the script.

## Quick Start

1. Add your real install names to `sample-sites.csv`.
2. Review `sample-commands.csv` and keep safe commands for first run.
   - You can rename these files to anything (for example, `client-a-sites.csv` and `safe-checks.csv`).
   - Just pass your chosen filenames when running the script.
3. Dry run:

```bash
./wpengine-wpcli-loop.sh --dry-run sample-sites.csv sample-commands.csv
```

4. Run for real:

```bash
./wpengine-wpcli-loop.sh sample-sites.csv sample-commands.csv
```

## Requirements

- WP Engine User Portal access
- Access to each target install/environment
- Local SSH key pair, with your public key added in WP Engine
- Ability to SSH to an install
- Bash 4+ on your local machine

## Files

- `wpengine-wpcli-loop.sh` - batch runner script
- `sample-sites.csv` - starter site list
- `sample-commands.csv` - starter command list
- `examples/sites/` - additional site-list examples
- `README-wpengine-wpcli-loop.md` - full documentation

For full details, troubleshooting, and failure behavior, see `README-wpengine-wpcli-loop.md`.
