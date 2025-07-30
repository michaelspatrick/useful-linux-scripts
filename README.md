# Useful Linux Scripts

A curated collection of Bash scripts for common server maintenance, automation, and debugging tasks. These tools are battle-tested on production environments and optimized for sysadmins, developers, and power users working with Linux systems (especially CentOS and Amazon Linux environments).

> ⚠️ Some scripts assume specific directory structures or software installed (e.g., `git`, `gh`, `mysqldump`, `multitail`). Review and customize for your environment.

## ✅ Requirements

- Bash (>= 4.x)
- Standard Linux utilities: `tar`, `gzip`, `mysqldump`, `rsync`, `find`, `zip`, etc.
- Optional:
  - `gh` (GitHub CLI) — for release automation
  - `multitail` — for log tailing convenience
  - `jq` — for JSON parsing if needed in future scripts

## 🚀 Usage

Clone this repository:

```bash
git clone https://github.com/michaelspatrick/useful-linux-scripts.git
cd useful-linux-scripts
chmod +x *.sh
```

Run a script:

```bash
./backup-www.sh
```

Or integrate into your cron jobs or deployment pipelines as needed.

## 🛠 Customization

Many scripts use environment variables or inline config sections at the top (e.g., backup targets, retention limits, or GitHub repo names). Always review and adjust settings before first use.

## 📄 License

MIT License — see [LICENSE](../LICENSE) for details.

---

**Created by [Michael Patrick](https://github.com/michaelspatrick)**  
For use with real-world servers, WordPress sites, and automation projects.
