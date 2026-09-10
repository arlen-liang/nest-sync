# nest-sync

One Git repository as the single source of truth for agent skills and project
logs, shared across machines and harnesses.

## What it is

`nest-sync` keeps two trees in one repository: `skills/<category>/<name>/` for
reusable agent skills (symlinked into each harness) and `logs/<project>/` for
project logs, progress notes and decision records. A single bash CLI
(`bin/nest`) wraps Git with seven subcommands: pull, push, sync, recall, bind,
link, status. No daemon, no external service.

## Why

Agents run on more than one machine. Without a shared source of truth, a skill
edited on one machine stays stale on another, and nobody can tell who changed
what, when, or why. `nest-sync` answers all three from Git history.

## Quick start

Self-hosting needs a server with a bare Git repository and SSH access for a
restricted `git` user. Full walkthrough: `deploy/web/nest.md`.

```bash
git clone git@nest.example.com:/srv/git/nest-sync.git ~/.nest/git
bash ~/.nest/git/install.sh
export PATH="$HOME/.nest/bin:$PATH"

nest pull                   # before work: fetch and relink skills
nest push -m "what changed" # after work: commit and push
nest recall <project>       # read a project log (read-only, works offline)
nest bind                   # bind a working folder to a log node
```

## Documentation

`docs/architecture.md`, `docs/security-model.md`, `docs/decisions.md`,
`examples/` (two example skills), and `deploy/README.md`.

## Known limitations

- **Single point of failure.** The server-side bare repository is the only
  authoritative copy; machine-local clones are not independent backups.
- **Not for large files.** Binaries and images are excluded by design.
- **Manual sync.** No file watcher, no background process.

## License

MIT. See `LICENSE`.
