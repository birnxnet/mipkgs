#!/usr/bin/env bash
# Update packages in pkgs/ to their latest upstream versions.
#
# For each package:
#   1. run its update script: pkgs/<pkg>/update.sh, or the update.sh of the
#      package it wraps (e.g. _1password-cli-beta -> _1password-cli/update.sh),
#      called with UPDATE_NIX_ATTR_PATH=<pkg> (nixpkgs convention)
#   2. otherwise run `nix-update <pkg>` (version + src/deps hashes, via ./default.nix)
#   3. build it; keep the change only if the build succeeds
#
# Usage: scripts/update-all.sh [--lock] [--no-commit] [pkg ...]
#   --lock       also run `nix flake update` first (kept only if all packages build)
#   --no-commit  stage successful updates instead of committing them
#   pkg ...      limit to these packages (default: every pkgs/*/package.nix)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

lock=0 commit=1 pkgs=() failed=() updated=()
for a in "$@"; do
  case $a in
    --lock) lock=1 ;;
    --no-commit) commit=0 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) pkgs+=("$a") ;;
  esac
done
if ((${#pkgs[@]} == 0)); then
  for f in pkgs/*/package.nix; do pkgs+=("$(basename "$(dirname "$f")")"); done
fi

# update.sh scripts use nix-shell / <nixpkgs>: pin them to this flake's nixpkgs
NIX_PATH="nixpkgs=$(nix eval --raw --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')"
export NIX_PATH

# unstaged or untracked changes (staged ones are earlier successful updates)
dirty() { ! git diff --quiet -- "$@" || [[ -n $(git ls-files --others --exclude-standard -- "$@") ]]; }

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

revert() {
  git restore --worktree -- "$@" 2>/dev/null
  git clean -fdq -- "$@"
}

keep() { # keep <message> <paths...>
  local msg=$1; shift
  git add -A -- "$@"
  if ((commit)); then git commit -q -m "$msg" -- "$@"; fi
}

if ((lock)) && [[ -n $(git status --porcelain -- flake.lock) ]]; then
  echo "flake.lock has uncommitted changes; skipping --lock"; lock=0
fi
if ((lock)); then
  log "flake.lock"
  nix flake update
  if git diff --quiet -- flake.lock; then
    echo "inputs up to date"
  else
    ok=1
    for p in "${pkgs[@]}"; do
      nix build --no-link -L ".#$p" || { ok=0; echo "!! $p fails on new inputs"; break; }
    done
    if ((ok)); then keep "flake.lock: update inputs" flake.lock; updated+=("flake.lock")
    else git restore -- flake.lock; failed+=("flake.lock"); fi
  fi
fi

for p in "${pkgs[@]}"; do
  log "$p"
  dir=pkgs/$p script=
  if [[ -f $dir/update.sh ]]; then
    script=$dir/update.sh
  elif base=$(grep -oP 'callPackage\s+\.\./\K[^/]+(?=/package\.nix)' "$dir/package.nix") &&
    [[ -f pkgs/$base/update.sh ]]; then
    script=pkgs/$base/update.sh
  fi

  paths=("$dir")
  [[ -n $script ]] && paths+=("$(dirname "$script")")
  if dirty "${paths[@]}"; then
    echo "!! uncommitted changes in ${paths[*]}; skipped"; failed+=("$p (dirty)"); continue
  fi

  if ! old=$(nix eval --raw ".#$p.version" 2>/dev/null); then
    echo "!! cannot evaluate $p"; failed+=("$p"); continue
  fi

  if [[ -n $script ]]; then
    echo "using $script"
    (cd "$(dirname "$script")" && UPDATE_NIX_ATTR_PATH=$p nix-shell ./update.sh "$p") >/dev/null
  else
    echo "using nix-update"
    nix-update "$p"
  fi
  rc=$?

  if ! dirty "${paths[@]}"; then
    if ((rc)); then echo "!! update failed"; failed+=("$p"); else echo "up to date ($old)"; fi
    continue
  fi

  new=$(nix eval --raw ".#$p.version" 2>/dev/null || echo "?")
  if ((rc == 0)) && [[ $new == "$old" ]]; then
    # e.g. a script that only rewrites a "Last updated" timestamp
    echo "up to date ($old); discarding non-version changes"
    revert "${paths[@]}"
    continue
  fi
  if ((rc == 0)) && nix build --no-link -L ".#$p"; then
    echo "updated $old -> $new"
    keep "$p: $old -> $new" "${paths[@]}"
    updated+=("$p $old -> $new")
  else
    echo "!! $p $old -> $new did not build; reverted"
    revert "${paths[@]}"
    failed+=("$p ($old -> $new)")
  fi
done

log "summary"
printf 'updated: %s\n' "${updated[@]:-none}"
printf 'failed:  %s\n' "${failed[@]:-none}"
((${#failed[@]} == 0))
