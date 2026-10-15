# Disk Hygiene

Rules and tooling that keep the DSH host from filling up. Established after the
2026-10-14 cleanup, which reclaimed **18 GB** (root filesystem went from 82% to
66% used).

Everything here is installed by `scripts/install-disk-hygiene.sh` and runs as a
systemd timer — no cron daemon is installed on this host.

## Files

| Path | Purpose |
| --- | --- |
| `scripts/dsh-disk-report` | Read-only report: usage, top consumers, Docker breakdown, regenerable caches, phantom space |
| `scripts/dsh-disk-guard` | Daily containment: stale build cache, dangling images, cheap caches, `btmp` cap, warning |
| `scripts/install-disk-hygiene.sh` | Installs both scripts, the units and the logrotate rule (idempotent) |
| `systemd/dsh-disk-guard.service` | Runs the guard (thresholds via `Environment=`) |
| `systemd/dsh-disk-guard.timer` | Daily 06:30 UTC + 5 min after boot, `Persistent=true` |
| `systemd/logrotate/dsh-disk-hygiene` | Rotates `btmp` and the guard log |

Installed to: `~/.local/bin/{dsh-disk-report,dsh-disk-guard}`,
`/etc/systemd/system/dsh-disk-guard.{service,timer}`,
`/etc/logrotate.d/dsh-disk-hygiene`,
`/etc/systemd/journald.conf.d/dsh-limits.conf`.

## Install

```bash
cd ~/workspace/dsh-server-setup
sudo ./scripts/install-disk-hygiene.sh            # or --user <name>
~/.local/bin/dsh-disk-report                      # current state, any time
```

Verify:

```bash
systemctl list-timers dsh-disk-guard.timer --no-pager
tail -20 ~/.local/state/dsh/disk-guard.log
```

## Where the space actually went (2026-10-14)

Measured with `df -h /`, `du -xhd2`, and `docker system df` — not guessed.

| Consumer | Size | Verdict |
| --- | --- | --- |
| **Docker build cache** | **40.9 GB** (13.4 GB reclaimable), plus 4.4 GB unused images | **Root cause.** Reclaimable |
| Runner images | `checktechout-prod-automation` 4.7 GB, `-payload` 1.97 GB | Needed — in active use |
| `~/.local/share/pnpm/store` | 2.6 GB | Prunable (kept the referenced half) |
| `~/.cache/camoufox` | 2.5 GB (2.1 GB fonts) | **Kept** — belongs to the scraping project |
| `~/.cache/ms-playwright` | 984 MB | Kept |
| `~/.dsh/sessions` | 997 MB (shell history) | Kept |
| `~/dsh-backups/20261001-151831` | 1.5 GB (one-off 990 MB tarball + a 514 MB copy) | Removable |
| `~/.npm` | 426 MB | Prunable |
| `/var/log/btmp` | **395 MB** — ~1,035,000 failed SSH logins | Truncated + rotated from now on |
| `/var/cache/apt` | 319 MB | Prunable |
| `/tmp` | 2.9 GB of scratch older than 3 days | Removable |

`/var/lib/docker` was **44 GB of the 96 GB disk** — over half of all used space
and almost entirely build cache. Two `docker compose build` runs are enough to
add several GB, and nothing ever removed the old layers.

## The standing rules

1. **Docker build cache is the default suspect.** Check `docker system df`
   before anything else. It is bounded twice over: cache older than 72 h is
   dropped daily, and a **20 GB hard ceiling** (`--max-used-space 20GB`) is
   enforced weekly. The size cap is the one that matters — an age-only rule
   still lets a burst of builds inside one day reach tens of GB. Recorded
   incidents: 45 GB build cache, 40.9 GB build cache, `ENOSPC` mid-deploy.
2. **Never `docker system prune -a` on this host.** It would remove the images
   behind containers that are legitimately stopped (coolify, pangolin, the
   project stacks). The guard only ever prunes *dangling* images and cache.
3. **Thresholds.** Warn at 80%, run the cheap prunes at 85%. Unattended
   `builder prune -af` stays off (`DSH_DISK_AUTOPRUNE=off`) because a cache wipe
   during a deploy costs a full rebuild.
4. **`btmp` is capped.** An internet-facing SSH port fills it with failed
   logins; it is rotated monthly and truncated past 50 MB. It is a symptom, not
   a bug — the attack surface itself belongs to the firewall.
5. **The journal is bounded** to 200 MB / 1 month (default `SystemMaxUse` is
   10% of the filesystem, which silently grows with the disk).
6. **Work in `/tmp` is scratch.** Anything older than 3 days is deleted; move
   deliverables out instead of citing them from `/tmp`.
7. **One-off backups do not accumulate in `~`.** A backup is removed once it is
   superseded; `dsh-backups/` is not a dump for restored trees that were never
   deleted. Branch backups are rotated too (weekly, 2 kept, 1 GB cap) — each
   `dsh-home.tar.gz` carries ~500 MB of `node_modules`.
8. **Caches that belong to a project are not disk-hygiene targets.**
   `~/.cache/camoufox`, `~/.cache/ms-playwright` and `node_modules` are
   re-download costs, not savings. Measure before deleting.
9. **Know how much free space a deploy needs.** A build cannot finish without
   room for its own layers, so keeping 20-30% free is a deploy prerequisite, not
   a comfort margin.


## Environment variables

Set in `dsh-disk-guard.service`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `DSH_DISK_WARN_PCT` | `80` | Log a full alert report at/above this usage |
| `DSH_DISK_PRUNE_PCT` | `85` | Run the cheap prunes at/above this usage |
| `DSH_DISK_AUTOPRUNE` | `off` | `on` also runs `docker builder prune -af` |
| `DSH_BUILD_CACHE_MAX_H` | `0` | Drop build cache older than N hours (`0` = never) |
| `DSH_BUILD_CACHE_MAX_GB` | `0` | Hard build-cache ceiling in GB, enforced weekly (`0` = never) |

## Manual recovery when the disk is critically full

Ordered by value per unit of risk — stop as soon as there is room:

```bash
docker builder prune -af        # 1. the big one, always safe
docker image prune -f           # 2. dangling layers only
pnpm store prune                # 3. keeps the referenced half
npm cache clean --force
sudo apt-get clean
sudo truncate -s 0 /var/log/btmp
find /tmp -maxdepth 1 -mtime +3 -exec rm -rf {} +
sudo journalctl --vacuum-size=200M
```

**Check for a running build first.** A `compose build` in flight both adds cache
and *replaces* the layers it is reusing, so the percentage moves in both
directions while you are cleaning. During the 2026-10-14 cleanup the host went
from 82% to 66%, then back up to 67% within four hours purely from builds
started by other work. Read the trend, not a single sample:

```bash
docker ps --format '{{.Names}}' | grep -i buildx     # is a build running?
ps aux | grep -E 'buildx|buildkit' | grep -v grep
```

The guard is safe under a running build: `builder prune` never touches cache
entries that are currently in use, and `image prune -f` only removes *dangling*
images (never a tagged image, never one behind a container). That is exactly why
`-a` is not automated.


Freeing space does **not** free it instantly if a process still holds a deleted
file open. Check with:

```bash
sudo lsof -nP | awk '/deleted/ {s+=$7} END {printf "%.2f GB\n", s/1073741824}'
```

## Reading `docker system df`

The four rows are not a clean partition of the disk and the "RECLAIMABLE" column
is not "free if you prune everything now":

- **Build Cache** reports the logical sum of cache entries, which share layers.
  It routinely reads 30 GB higher than the space pruning actually returns.
- **Images "reclaimable"** counts images that no container references *right
  now*, including the previous version of an image you just rebuilt. Those come
  back on the next rollback, and `image prune -f` will not touch them — only
  `-a` would, which is why it is not automated.
- **Volumes "reclaimable"** belongs to databases that are merely stopped. Treat
  it as data, never as waste.

So: use the *percentage* from `df` as the trigger, `du` to rank directories, and
`docker system df` only to identify which kind of waste is growing.

## `du` versus `df`

`du -xsh /` reports roughly half of what `df` does on this host (32 GB vs
63 GB), because `/var/lib/docker` and the overlay mounts are not fully walked by
`du -x`. **Trust `df` for totals and `du` only for ranking directories.** The
guard and the report both read `df -P /` for the percentage.

## Rotating a public-service log that is not covered here

If a new unbounded log appears (a browser profile, a build log, a container
log), add it to `systemd/logrotate/dsh-disk-hygiene` rather than truncating it by
hand, so the cap survives the next reboot.
