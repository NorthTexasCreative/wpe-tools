# WP Engine WP-CLI Loop

Run the same WP-CLI command list across multiple WP Engine installs over SSH.

> This repository is **not** a DDEV project. Run commands directly in your local shell.

## Quick Start

1. Add your real install names to `sample-sites.csv`.
2. Review `sample-commands.csv` and keep safe commands for first run.
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
- Ability to SSH to an install as:

```bash
ssh <install>@<install>.ssh.wpengine.net
```

## Files

- `wpengine-wpcli-loop.sh` - batch runner script
- `sample-sites.csv` - starter site list
- `sample-commands.csv` - starter command list
- `README-wpengine-wpcli-loop.md` - full documentation

For full details, troubleshooting, and failure behavior, see `README-wpengine-wpcli-loop.md`.
