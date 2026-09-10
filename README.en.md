# nest-sync

[中文](README.md) | **English**

nest-sync puts agent skills and project logs into one Git repository. The first
version went live on a server in August 2026 and has been in daily use across a
few machines since.

The situation it is built for: the same set of agents, running on different
servers.

## Why

It started with memos. Context was recalled from a memo per agent, and once there
were several agents, keeping those memos in step became manual labour: the same
context had to be stored in several places, and editing one copy told the others
nothing.

Skills brought a further layer of trouble: a skill improves by iteration, and the
ideas come in clusters. Several tasks running at once can each throw up a revision
within the same stretch of time, and each one sits in its own session, collecting
nowhere. Even once collected they have to be distributed, and every harness keeps
its own skills directory — one per machine, and laying them out by hand costs half
a day.

Then came the constraint of connection: agents on a local machine are not always
online, and agents in the cloud cannot reach the local files that change fastest.
The two sides cannot see each other. Agent-to-agent communication had nowhere to
live either.

All of this points at the same gap: context, skills and material each sit in a
corner of their own. nest-sync's answer is a shared one — a self-hosted Git
repository as the single source of truth. Everything else is packaging around it.

## Architecture at a glance

```
Device
  ~/.nest/git              Git working copy; connection key pinned by repo-level core.sshCommand
  ~/.nest/bin/nest         A single bash script, seven subcommands
  <harness>/skills/<name>  One-level symlink → repo skills/<category>/<skill>
        │
        │  ssh git@<your-server>  (the git user may only send and receive the repo)
        ▼
Server
  /srv/git/nest-sync.git      Bare repository, the only authoritative copy
    hooks/pre-receive         Server-side key gate, cannot be bypassed
  /opt/nest-enroll/           Enrollment service (unprivileged user, loopback only)
  /usr/local/sbin/nest-keys   Key roster management (root, server-local only)
  /var/www/nest/              Landing page and enrollment form
  /var/lib/nest-enroll/       Pending queue, decisions, audit log
```

Three design choices are worth calling out on their own.

| Mechanism | What it does |
|---|---|
| Skills distributed by symlink | There is only one real copy, in the repository; each harness's skills directory holds a symlink. Edit the real copy and every harness picks it up immediately — "a second copy drifting" does not exist structurally |
| Working folders joined by a door-plate pointer | Project materials and attachments stay in their own folders and never enter the repository; a `.nest` pointer file records which `logs/<node>/` it belongs to. Pointers nest, so nested directories mean nested nodes. And because those folders are not Git repositories at all, the project materials physically cannot be pushed to the cloud |
| Two key gates | A local `pre-commit` and a server-side `pre-receive`, each scanning once. The local one can be skipped with `--no-verify`; the server-side one cannot. The first guards against slips, the second against intent |

## Commands

| Command | Purpose |
|---|---|
| `nest pull` | Before work: fetch the latest from the server and rebuild the skill symlinks |
| `nest push -m "message"` | After work: commit and push local changes; on rejection, retry once with an automatic rebase |
| `nest sync -m "message"` | Pull then push, in one shot |
| `nest recall [project] [keyword]` | Recall logs. Strictly read-only, works offline and with a dirty working tree |
| `nest bind [slug]` | Bind the current working directory to a node under `logs/` |
| `nest status` | See how local and server diverge |
| `nest link [--force]` | Rebuild skill symlinks, filterable by category |

## Quick start

You need a server that can run SSH and Git. The full self-hosting walkthrough
is in `deploy/web/nest.md` (in Chinese).

```bash
# 1. Generate a dedicated key (ed25519 only)
ssh-keygen -t ed25519 -f ~/.ssh/nest_key -N "" -C "identifier for this machine"

# 2. Submit an enrollment request, then report the fingerprint to the
#    administrator through a different channel
#    Do not skip this step: the shared password on the site only stops
#    scanners — what actually stops an impersonated submission is the
#    cross-channel fingerprint check

# 3. Install once approved
curl -sS https://nest.example.com/install.sh -o /tmp/nest-install.sh
bash /tmp/nest-install.sh \
  --repo git@nest.example.com:/srv/git/nest-sync.git \
  --key ~/.ssh/nest_key --name <identifier for this machine> -y

# 4. Verify
nest status && nest recall <project>
```

Day to day there are only two rules: `nest pull` before work, `nest push` after
work. If you cannot be bothered to tell them apart, `nest sync`.

## Documentation

| File | Contents |
|---|---|
| `docs/architecture.md` (in Chinese) | System architecture: Git as the hub, subcommands, symlink distribution, the door-plate mechanism, the enrollment flow |
| `docs/security-model.md` (in Chinese) | Trust boundaries and data classification, the two gates, why keys are not synced across machines |
| `docs/decisions.md` (in Chinese) | Key design decisions and their trade-offs, including a "things we deliberately do not do" list |
| `examples/nest-skill/` (in Chinese) | Example skill: what a nest skill should look like, with progressive loading of references |
| `examples/skill-authoring/` (in Chinese) | Example skill: the authoring conventions for turning one piece of real work into a reusable skill |
| `deploy/README.md` | What the server-side deployment consists of and how to redeploy it |

## Known limitations

The biggest caveat is the **single point**: the bare repository on the server is
the only authoritative copy, and every device's working copy ultimately falls
back to it, so it does not count as an independent backup. The repository can be
cloned elsewhere at any time, but nothing guarantees that you will ever remember
to do it. For real production use, a third physical location is the missing
piece.

Next, it is **not suited to large files**. Binaries and Office documents stay out
of the repository entirely — once they are in Git history they occupy space
permanently and cannot be fully removed. The repository is meant as a plain-text
content library; sharing images or attachments needs another route.

Finally, syncing is entirely manual: no file watcher, no background process.
Not pushing means not having written anything.

## License and maintenance

MIT, see `LICENSE`.

This is a personal showcase project: an attempt to write down a setup I use
myself in a readable form. Issues are welcome, but there is no promised response
time and no commitment to ongoing maintenance; large changes made without prior
discussion are quite likely to be closed outright — see `docs/decisions.md`. Read
`CONTRIBUTING.md` before contributing.
