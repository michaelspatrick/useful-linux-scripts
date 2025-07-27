#!/bin/bash

set -e

# ─── CONFIG ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(basename "$PWD")"
VERSION="$1"
TAG="v$VERSION"
ZIP_NAME="../${SCRIPT_DIR}-${VERSION}.zip"

EXCLUDES=(
  ".git*"
  "release.sh"
  "*.zip"
  "README.md"
  "readme.txt"
  "build/*"
)

# ─── HELPERS ─────────────────────────────────────────────────────────────
abort() {
  echo "❌ $1"
  exit 1
}

# ─── CHECKS ─────────────────────────────────────────────────────────────
[[ -z "$VERSION" ]] && abort "Usage: ./release.sh <version>"

command -v git >/dev/null || abort "Git is not installed"
command -v gh >/dev/null || abort "GitHub CLI (gh) is not installed"

if git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "✅ Git repo detected"
else
  echo "📁 Not in a Git repo. Initializing..."
  git init
  git add .
  git commit -m "Initial commit"
fi

# ─── FIX DUBIOUS OWNERSHIP ─────────────────────────────────────────────
if ! git config --show-origin --get-regexp 'safe.directory' | grep -q "$PWD"; then
  echo "⚠️ Marking current directory as safe for Git..."
  git config --global --add safe.directory "$PWD"
fi

# ─── REMOTE SETUP ───────────────────────────────────────────────────────
if ! git remote | grep -q origin; then
  echo "🔗 No 'origin' remote found."
  read -p "Enter your GitHub username: " GH_USER
  REPO_NAME="$SCRIPT_DIR"
  if gh repo view "$GH_USER/$REPO_NAME" &>/dev/null; then
    echo "🔁 Repo exists. Adding remote..."
    git remote add origin "https://github.com/$GH_USER/$REPO_NAME.git"
  else
    echo "🚀 Creating GitHub repo..."
    gh repo create "$GH_USER/$REPO_NAME" --public --source=. --push || abort "Failed to create repo"
  fi
fi

# ─── PUSH MAIN BRANCH IF NEEDED ────────────────────────────────────────
if ! git ls-remote --exit-code origin main &>/dev/null; then
  echo "⬆️ Pushing main branch to origin..."
  git checkout -B main
  git push -u origin main || abort "Failed to push main branch"
else
  echo "✅ main branch already exists on origin"
fi

# ─── ZIP ALL FILES ─────────────────────────────────────────────────────
echo "📦 Creating ZIP: $ZIP_NAME"
zip -r "$ZIP_NAME" . -x "${EXCLUDES[@]}" || abort "Failed to create ZIP"

# ─── COMMIT AND PUSH CHANGES ───────────────────────────────────────────
git add .
git commit -m "Release v$VERSION" || echo "ℹ️ Nothing new to commit"

# Ensure sync with remote
if ! git diff --quiet origin/main..main || ! git diff --quiet main..origin/main; then
  echo "🔄 Syncing with remote main..."
  git pull --rebase origin main || abort "Rebase failed"
fi

git push origin main || echo "⚠️ Failed to push changes to main"

# ─── TAG AND RELEASE ───────────────────────────────────────────────────
git tag -f "$TAG"
git push origin "$TAG" || echo "⚠️ Could not push tag (already exists?)"

if gh release view "$TAG" &>/dev/null; then
  echo "🗑️ Existing release found. Deleting..."
  gh release delete "$TAG" --yes || abort "Failed to delete existing release"
fi

echo "🚀 Creating GitHub release for $TAG..."
gh release create "$TAG" "$ZIP_NAME" --title "Version $VERSION" --notes "Release version $VERSION" || abort "Failed to create GitHub release"

echo "✅ Release v$VERSION completed successfully."

