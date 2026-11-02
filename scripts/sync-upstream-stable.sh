#!/bin/sh
# Keeps this fork tracking DeepSeek Harness's newest release.
#
# The fork has two long-lived branches:
#   stable  a clean mirror of upstream's newest published release tag (dsh-v*)
#   intel   `stable` plus this fork's Intel (x86_64) macOS build workflow and
#           docs (the default branch)
#
# This script finds the newest published, non-draft release on
# github.com/deepseek-ai/deepseek-harness, moves `stable` to that tag, merges
# it into `intel`, and pushes both. A conflict aborts the merge, leaves the
# branches as they were, and (in Actions) opens one issue with the conflicted
# files so the merge can be finished by hand. It is run daily by
# .github/workflows/upstream-sync.yml and can be run by hand from a checkout of
# `intel`:
#
#   scripts/sync-upstream-stable.sh            # sync and push
#   DRY_RUN=1 scripts/sync-upstream-stable.sh  # report only, change nothing
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

upstream_url=${UPSTREAM_URL:-https://github.com/deepseek-ai/deepseek-harness.git}
upstream_repo=${UPSTREAM_REPO:-deepseek-ai/deepseek-harness}
remote=${UPSTREAM_REMOTE:-upstream}
intel_branch=${INTEL_BRANCH:-intel}
stable_branch=${STABLE_BRANCH:-stable}

git config user.name >/dev/null 2>&1 || git config user.name "dsh-intel-sync"
git config user.email >/dev/null 2>&1 || git config user.email "${SYNC_EMAIL:-dsh-intel-sync@users.noreply.github.com}"

if ! git remote get-url "$remote" >/dev/null 2>&1; then
  git remote add "$remote" "$upstream_url"
fi
git fetch --force --tags "$remote"

# Upstream's releases are all prerelease (rc/alpha) tags, so "newest release"
# is the newest published, non-draft GitHub release rather than the newest
# non-prerelease tag. gh is present in Actions; local runs fall back to the
# newest tag by tag date.
if [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  latest=$(gh release list --repo "$upstream_repo" --limit 50 \
    --json tagName,isDraft,publishedAt \
    --jq '[.[] | select(.isDraft == false)] | sort_by(.publishedAt) | last | .tagName')
else
  latest=$(git tag --list 'dsh-v*' --sort=-creatordate | head -n 1)
fi
if [ -z "$latest" ] || [ "$latest" = "null" ]; then
  echo "No published release found on $upstream_repo" >&2
  exit 1
fi
target=$(git rev-parse "$latest^{commit}")
echo "Upstream release: $latest ($target)"

if [ "${DRY_RUN:-}" = 1 ]; then
  echo "DRY_RUN=1: not moving $stable_branch or merging into $intel_branch"
  exit 0
fi

# Mirror the release tag into the fork, so the build workflow can check it out.
if ! git ls-remote --tags origin "refs/tags/$latest" | grep -q .; then
  git push origin "refs/tags/$latest:refs/tags/$latest"
  echo "tag $latest -> origin"
fi

moved=false
current_stable=$(git ls-remote --heads origin "refs/heads/$stable_branch" | cut -f1)
if [ "$current_stable" != "$target" ]; then
  git push origin "$target:refs/heads/$stable_branch"
  echo "$stable_branch -> $latest"
  moved=true
else
  echo "$stable_branch already at $latest"
fi

if [ "$(git rev-parse --abbrev-ref HEAD)" != "$intel_branch" ]; then
  git checkout -q "$intel_branch"
fi
# The remote-tracking ref follows the push above, so keep it current for the
# status line below.
git fetch -q origin "$intel_branch" || true

if git merge-base --is-ancestor "$target" HEAD; then
  echo "$intel_branch already contains $latest"
  if [ "$moved" = true ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "Upstream release **$latest** mirrored to \`$stable_branch\`; \`$intel_branch\` already contained it." >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

summary="Upstream release **$latest**"
if git merge --no-edit -m "Merge upstream release $latest into $intel_branch" "$target"; then
  git push origin "$intel_branch"
  echo "$intel_branch merged $latest"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$summary merged into \`$intel_branch\`." >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

# Conflict: keep the branches as they were and say exactly what clashed.
conflicted=$(git diff --name-only --diff-filter=U)
git merge --abort
{
  echo "Upstream release $latest could not be merged into $intel_branch automatically."
  echo
  echo "Conflicted files:"
  printf '%s\n' "$conflicted" | sed 's/^/- /'
  echo
  echo "Resolve locally, then re-run the Track upstream release workflow:"
  echo
  echo '```sh'
  echo "git fetch upstream --tags"
  echo "git checkout $intel_branch"
  echo "git merge $latest   # fix conflicts, commit"
  echo "git push origin $intel_branch"
  echo '```'
} >"$root/.git/upstream-sync-conflict.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "**Conflict** merging upstream release $latest into \`$intel_branch\`:" >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' '```' >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' "$conflicted" >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' '```' >> "$GITHUB_STEP_SUMMARY"
fi
if [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  title="Upstream sync conflict: $latest"
  existing=$(gh issue list --state open --search "$title in:title" --json number --jq '.[0].number' 2>/dev/null || true)
  if [ -n "$existing" ]; then
    echo "Conflict already reported in issue #$existing" >&2
    gh issue comment "$existing" --body-file "$root/.git/upstream-sync-conflict.md" >/dev/null 2>&1 || true
  else
    gh issue create --title "$title" --body-file "$root/.git/upstream-sync-conflict.md" >/dev/null || true
  fi
fi
echo "Conflict merging $latest into $intel_branch; see .git/upstream-sync-conflict.md" >&2
exit 1
