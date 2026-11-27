#!/usr/bin/env bash
# One command to bring Firebase up to date with the repo (meant for Cloud Shell).
#
#   bash tools/deploy.sh                      # main -> rules, indexes, storage, hosting, functions
#   bash tools/deploy.sh --branch my-branch   # deploy another branch as it is
#   bash tools/deploy.sh --merge my-branch    # merge my-branch into main, push main, then deploy main
#   bash tools/deploy.sh --only rules,functions
#   bash tools/deploy.sh --force              # let functions deploy delete removed functions without asking
#
# --only takes any of: rules, indexes, storage, hosting, functions.
# The checkout in ~/shadchan is a deploy copy: it is reset to origin/<branch> on every run.

set -euo pipefail

PROJECT="shadchan-gilad"
REPO_URL="https://github.com/GiladShtruz/shadchan.git"
DIR="${SHADCHAN_DIR:-$HOME/shadchan}"
BRANCH="main"
MERGE=""
ONLY="rules,indexes,storage,hosting,functions"
FORCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --merge)  MERGE="$2"; shift 2 ;;
    --only)   ONLY="$2"; shift 2 ;;
    --force)  FORCE="--force"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
want() { case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

say "project $PROJECT"
gcloud config set project "$PROJECT" >/dev/null

say "git ($BRANCH)"
[ -d "$DIR/.git" ] || git clone "$REPO_URL" "$DIR"
cd "$DIR"
git fetch --prune origin
if [ -n "$MERGE" ]; then
  git checkout -q -B main origin/main
  git merge --no-edit "origin/$MERGE"
  git push origin main
  BRANCH="main"
fi
git checkout -q -B "$BRANCH" "origin/$BRANCH"
echo "at $(git rev-parse --short HEAD): $(git log -1 --pretty=%s)"

if want functions; then
  say "npm ci (functions)"
  (cd functions && npm ci)
fi

say "firebase login"
firebase projects:list >/dev/null 2>&1 || firebase login --no-localhost

# Everything except functions goes in one call.
targets=()
want rules   && targets+=(firestore:rules)
want indexes && targets+=(firestore:indexes)
want storage && targets+=(storage)
want hosting && targets+=(hosting)
if [ ${#targets[@]} -gt 0 ]; then
  say "deploy ${targets[*]}"
  (IFS=,; firebase deploy --only "${targets[*]}" --project "$PROJECT")
fi

if want functions; then
  say "deploy functions"
  FUNCTIONS_DISCOVERY_TIMEOUT=60 firebase deploy --only functions --project "$PROJECT" $FORCE
fi

say "done: $BRANCH @ $(git rev-parse --short HEAD)"
