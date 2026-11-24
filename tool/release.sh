#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
cd "$root"

mode=""
want_version=""
rebuild=0
do_push=0
remote=origin
assume_yes=0
dry_run=0

usage() {
  cat <<'EOF'
Usage: tool/release.sh <pre|stable> [options]

  pre                Tag the next vX.Y.Z-pre.N prerelease on HEAD, no commit.
                     On a fork version it tags vX.Y.Z-myl7.M-rcN instead.
  stable             Write the changelog, pause for edits, commit it, and
                     tag vX.Y.Z or vX.Y.Z-myl7.M.

The fork keeps its own build number in pubspec.yaml; CI still takes the app
version from the tag.

Options:
  --version X.Y.Z    Target app version, plain or with the fork suffix, as in
                     0.9.3-myl7.1. Defaults to the pubspec version: when the
                     plain version is already tagged, the first -myl7.1 fork
                     release on it is targeted; an already tagged fork version
                     bumps its fork patch (-myl7.1 -> -myl7.2).
  --rebuild          With pre: rebuild the newest prerelease instead of
                     starting the next one. Upstream tags gain +M; fork rc
                     tags gain +M after the rc number.
  --push             Push the branch and the tag once the local steps pass.
  --remote NAME      Remote to push to (default origin).
  --yes              Skip the confirmation prompt and the changelog pause.
  --dry-run          Report the plan and exit without changing anything.
  -h, --help         Show this help.

Examples:
  tool/release.sh pre --push            # v0.8.97-pre.1, or v0.9.3-myl7.1-rc1
  tool/release.sh pre --rebuild --push  # v0.8.97-pre.1+1, or -rc1+1
  tool/release.sh stable --push         # v0.8.97, or v0.9.3-myl7.1
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    pre | stable)
      [[ -z "$mode" ]] || die "mode given twice: $mode and $1"
      mode="$1"
      ;;
    --version)
      shift || die "--version needs a value"
      want_version="$1"
      ;;
    --version=*) want_version="${1#*=}" ;;
    --rebuild) rebuild=1 ;;
    --push) do_push=1 ;;
    --remote)
      shift || die "--remote needs a value"
      remote="$1"
      ;;
    --remote=*) remote="${1#*=}" ;;
    --yes | -y) assume_yes=1 ;;
    --dry-run) dry_run=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$mode" ]] || {
  usage >&2
  exit 64
}

if [[ -n "$want_version" && ! "$want_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-myl7\.[0-9]+)?$ ]]; then
  die "--version must look like 0.8.97 or 0.9.3-myl7.1, got: $want_version"
fi

pubspec_version() {
  sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+(-myl7\.[0-9]+)?).*/\1/p' pubspec.yaml
}

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree has uncommitted changes; commit or stash them first"
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" != "HEAD" ]] || die "detached HEAD; check out a branch first"
if [[ "$branch" != "main" ]]; then
  echo "note: releasing from '$branch', not main. CI triggers on the tag, so"
  echo "      this publishes '$branch' while main stays behind."
fi

current="$(pubspec_version)"
[[ -n "$current" ]] || die "could not read the version from pubspec.yaml"

bumped=0
if [[ -n "$want_version" ]]; then
  version="$want_version"
elif git rev-parse -q --verify "refs/tags/v$current" >/dev/null; then
  base="${current%%-*}"
  if [[ "$current" == *-myl7.* ]]; then
    mylpatch="${current##*-myl7.}"
    version="$base-myl7.$((mylpatch + 1))"
  else
    version="$base-myl7.1"
  fi
  echo "pubspec is at $current, which is already tagged; targeting $version"
else
  version="$current"
fi

git rev-parse -q --verify "refs/tags/v$version" >/dev/null &&
  die "v$version is already tagged; pass --version with the next one"

if [[ "$version" != "$current" ]]; then
  bumped=1
fi

if [[ "$mode" != "stable" ]]; then
  if [[ "$version" == *-myl7.* ]]; then
    # The changelog grammar (tool/src/changelog/git.dart) and every existing
    # tag write the stage without a dot: v0.9.3-myl7.2-rc1, never -rc.1.
    last="$(git tag --list "v$version-rc*" |
      sed -n "s/^v$version-rc\([0-9]*\)\(+[0-9]*\)\{0,1\}$/\1/p" |
      sort -n | tail -1)"
    if ((rebuild)); then
      [[ -n "$last" ]] || die "no v$version-rcN to rebuild; run without --rebuild first"
      builds="$(git tag --list "v$version-rc$last+*" |
        sed -n "s/^v$version-rc$last+\([0-9]*\)$/\1/p" | sort -n | tail -1)"
      tag="v$version-rc$last+$(((${builds:-0}) + 1))"
    else
      tag="v$version-rc$(((${last:-0} + 1)))"
    fi
  else
    last="$(git tag --list "v$version-pre.*" |
      sed -n "s/^v$version-pre\.\([0-9]*\)\(+[0-9]*\)\{0,1\}$/\1/p" |
      sort -n | tail -1)"
    if ((rebuild)); then
      [[ -n "$last" ]] || die "no v$version-pre.N to rebuild; run without --rebuild first"
      builds="$(git tag --list "v$version-pre.$last+*" |
        sed -n "s/^v$version-pre\.$last+\([0-9]*\)$/\1/p" | sort -n | tail -1)"
      tag="v$version-pre.$last+$(((${builds:-0}) + 1))"
    else
      tag="v$version-pre.$(((${last:-0} + 1)))"
    fi
  fi
else
  ((rebuild == 0)) || die "--rebuild only applies to pre"
  tag="v$version"
fi

rewritten=""
if ((bumped)) && [[ "$mode" == "stable" ]]; then
  rewritten=' (pubspec will be rewritten)'
fi

echo
echo "mode      : $mode"
echo "branch    : $branch"
echo "version   : $current -> $version$rewritten"
echo "tag       : $tag"
if [[ "$mode" != "stable" ]]; then
  echo "changelog : rendered by CI from build --unreleased; nothing committed"
  if [[ "$version" == *-myl7.* ]]; then
    echo "publishes : GitHub prerelease with artifacts (fork rc tag)"
  else
    echo "publishes : build artifacts + Telegram only, no GitHub release"
  fi
else
  echo "changelog : CHANGELOG.md + changelog.json regenerated and committed"
  echo "publishes : GitHub release with artifacts, SHA256SUMS, Homebrew cask, Telegram link"
fi
echo "push      : $([[ $do_push == 1 ]] && echo "yes (to $remote)" || echo 'no (printed at the end)')"
echo

committed=0
restore() {
  ((committed)) && return 0
  git checkout -- pubspec.yaml changelog.json CHANGELOG.md 2>/dev/null || true
}
trap restore EXIT

if ((bumped)); then
  sed -i.bak "s/^version: [^+]*/version: $version/" pubspec.yaml
  rm -f pubspec.yaml.bak
fi
tool/bump_version.sh minor

echo "--- release notes for $tag ---"
if build_error="$(dart run tool/changelog.dart build --unreleased 2>&1 >/dev/null)"; then
  dart run tool/changelog.dart render release 2>/dev/null |
    sed -n '/changelog:begin/,/changelog:end/p' | sed '1d;$d'
else
  echo "(preview unavailable: 'build --unreleased' failed)"
  printf '%s\n' "$build_error" | sed 's/^/  /'
fi
git checkout -- changelog.json 2>/dev/null || true
echo "--- end of notes ---"
echo

if ((dry_run)); then
  echo "dry run: nothing was changed."
  exit 0
fi

if ((assume_yes == 0)); then
  if [[ ! -r /dev/tty ]]; then
    die "no terminal to confirm on; pass --yes to run unattended"
  fi
  while true; do
    read -r -p "Proceed with $tag? [y/n] " reply </dev/tty ||
      die "no answer read; pass --yes to run unattended"
    case "$reply" in
      [yY] | [yY][eE][sS]) break ;;
      [nN] | [nN][oO])
        echo "Cancelled. Nothing was changed."
        exit 0
        ;;
      *) echo "Please answer y or n." ;;
    esac
  done
fi

if [[ "$mode" == "stable" ]]; then
  dart run tool/changelog.dart release --version "$version"
  if ((assume_yes == 0)); then
    echo
    echo "changelog.json now holds the $tag notes. Edit their wording, merge"
    echo "entries with \"merges\" or leave commits out with \"omit\" (see"
    echo ".agents/commands.md), then press Enter; Ctrl-C undoes the release."
    while true; do
      read -r <"/dev/tty" || die "no answer read; pass --yes to run unattended"
      dart run tool/changelog.dart markdown &&
        dart run tool/changelog.dart verify &&
        break
      echo "Fix changelog.json, then press Enter again; Ctrl-C undoes the release."
    done
  else
    dart run tool/changelog.dart verify
  fi
  echo
  git --no-pager diff --stat -- CHANGELOG.md changelog.json pubspec.yaml
  echo
  git add CHANGELOG.md changelog.json pubspec.yaml
  git commit -m "chore(release): v$version"
  committed=1
elif ! git diff --quiet -- pubspec.yaml; then
  git add pubspec.yaml
  git commit -m "chore: bump version to $(sed -n 's/^version: //p' pubspec.yaml)"
  committed=1
else
  committed=1
fi

git tag "$tag"
echo "tagged $tag at $(git rev-parse --short HEAD)"

if ((do_push)); then
  git push "$remote" "$branch"
  git push "$remote" "$tag"
  echo "pushed $branch and $tag to $remote"
else
  echo
  echo "Nothing was pushed. To publish:"
  echo "  git push $remote $branch && git push $remote $tag"
fi
