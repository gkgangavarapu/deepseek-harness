# Intel macOS builds (this fork)

Upstream `deepseek-ai/deepseek-harness` packages its desktop app for Apple silicon only. This fork keeps an unsigned, ad-hoc-signed Intel (x86_64) build of the newest upstream release, produced only when asked.

## Branches

| Branch | What it is |
| --- | --- |
| `stable` | A clean mirror of upstream's newest published release tag (`dsh-v*`). Never carries fork changes. |
| `intel` | Default branch. `stable` plus the Intel build workflow and this document. All Intel builds come from here. |
| `master` | Unchanged. It is upstream's development branch as of the fork, and older Intel experiments (`feat/desktop-macos-x64-ci`, `upgrade/rc.3-mac-x64`) predate this setup. |

## Tracking upstream releases

`.github/workflows/upstream-sync.yml` runs daily at 04:17 UTC (09:47 IST) and on demand from the Actions tab. It asks GitHub for the newest published, non-draft release on `deepseek-ai/deepseek-harness` — every upstream release is currently a prerelease tag such as `dsh-v0.2.1-rc.5`, so "newest release" means the newest published one, not a stable semver release — force-updates `stable` to that tag, merges it into `intel`, and pushes. If the merge conflicts, it aborts the merge, leaves `intel` untouched (`stable` has already moved to the new tag), and opens one issue named `Upstream sync conflict: dsh-vX.Y.Z` listing the conflicted files.

The logic lives in `scripts/sync-upstream-stable.sh` and can be run by hand from a checkout of `intel`:

```sh
scripts/sync-upstream-stable.sh              # sync and push
DRY_RUN=1 scripts/sync-upstream-stable.sh    # report only
```

`intel` is the fork's default branch, so GitHub schedules this workflow from it. Workflows are enabled in this fork; if GitHub ever pauses them (a fork whose Actions were never enabled starts paused), open the Actions tab and click **Enable workflows**.

## Building when asked

`.github/workflows/build-macos-intel.yml` is manual only and never scheduled. It runs on GitHub's standard Intel x64 macOS 26 runner (`macos-26-intel`), builds `pnpm --dir apps/desktop run package:mac:x64:unsigned`, and attaches the DMG plus `SHA256SUMS` to a release in this fork named `DeepSeek Harness <version> (Intel)` with tag `intel-v<version>`.

The default `ref` is `latest`: the workflow asks GitHub for the newest published upstream release and builds that tag, so a build always matches the release it is named after even if the daily sync has not run yet. Pass a commit, branch, or tag to build something else; the sync also mirrors each upstream release tag into this fork, so `dsh-v*` tags can be checked out here.

This exists for the case where no Intel build machine is available locally. The unsigned packaging path needs no signing identity and no Apple credentials, so it runs on a standard GitHub-hosted runner.

Building the same DMG locally on an Intel Mac is possible with Node 24 and pnpm:

```sh
pnpm install --frozen-lockfile
pnpm --dir apps/desktop run package:mac:x64:unsigned
```

The DMG lands in `apps/desktop/.desktop-build/targets/mac-x64/unsigned-artifacts/`.

## Installing and updating

The DMG is unsigned and not notarized. Install by opening the DMG and dragging `DeepSeek Harness.app` to Applications; the first launch needs right-click → **Open** (or `xattr -dr com.apple.quarantine "/Applications/DeepSeek Harness.app"`).

The unsigned packaging path strips every release setting, so this build never auto-updates and is not tied to upstream's update feed. To update, install a newer `intel-v*` release from this fork.
