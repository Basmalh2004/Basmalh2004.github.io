#!/usr/bin/env bash
# Publish this folder to GitHub Pages at https://<username>.github.io
# Usage: bash deploy.sh <github-username>
# Needs: gh logged in (gh auth login), git. Safe to re-run.
set -euo pipefail

USER_NAME="${1:?usage: bash deploy.sh <github-username>}"
REPO="$USER_NAME/$USER_NAME.github.io"
SITE="https://$USER_NAME.github.io"
cd "$(dirname "$0")"

gh auth status >/dev/null 2>&1 || { echo "Not logged in. Run: gh auth login"; exit 1; }
LOGIN="$(gh api user --jq .login)"
if [ "${LOGIN,,}" != "${USER_NAME,,}" ]; then
  echo "gh is logged in as '$LOGIN', not '$USER_NAME'."; exit 1
fi

# 1. Repository
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  echo "Creating public repo $REPO"
  gh repo create "$REPO" --public --description "Personal site"
fi

# 2. Local git + commit (only when something changed)
[ -d .git ] || git init -q -b main
git config user.name  "$(gh api user --jq '.name // .login')"
git config user.email "$(gh api user --jq '.id')+$LOGIN@users.noreply.github.com"
touch .nojekyll
git add -A
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -q -m "Update site"
  echo "Committed: $(git log -1 --format=%h)"
fi
git branch -M main
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "https://github.com/$REPO.git"
else
  git remote add origin "https://github.com/$REPO.git"
fi
gh auth setup-git >/dev/null 2>&1 || true
git push -q -u origin main

# 3. Pages from main / root
if gh api "repos/$REPO/pages" >/dev/null 2>&1; then
  gh api -X PUT "repos/$REPO/pages" -f "source[branch]=main" -f "source[path]=/" >/dev/null || true
else
  gh api -X POST "repos/$REPO/pages" -f "source[branch]=main" -f "source[path]=/" >/dev/null
fi
echo "Pages enabled for $REPO"

# 4. Wait for the site to answer (up to ~3 minutes)
for i in $(seq 1 36); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$SITE/" || true)"
  if [ "$code" = "200" ]; then echo "Live: $SITE"; exit 0; fi
  sleep 5
done
echo "Not live yet (last HTTP $code). GitHub can take a few more minutes: $SITE"
exit 2
