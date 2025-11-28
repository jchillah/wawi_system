#!/usr/bin/env bash

set -e

REPO="jchillah/wawi_system"
OWNER="jchillah"
PROJECT_TITLE="WaWi System – Roadmap"

echo "🚀 Initialisiere WiWa System GitHub Enterprise Setup..."
echo "------------------------------------------------------"

#
# 1) Sicherstellen, dass Repo existiert
#
echo "🔍 Prüfe Repository..."
if gh repo view "$REPO" > /dev/null 2>&1; then
  echo "✔ Repo existiert: $REPO"
else
  echo "❌ Repo existiert nicht – Script abbrechen."
  exit 1
fi

#
# 2) Branches anlegen falls nicht vorhanden
#
create_branch() {
  local BR=$1
  if git ls-remote --heads origin "$BR" | grep "$BR" > /dev/null; then
    echo "✔ Branch $BR existiert"
  else
    echo "🆕 Erstelle Branch $BR"
    git checkout -b "$BR"
    git push -u origin "$BR"
  fi
}

create_branch main
create_branch develop

git checkout develop

#
# 3) Branch Protection für main + develop
#
apply_protection() {
  local BRANCH=$1
  echo "🛡️  Setze Branch Protection für $BRANCH..."

  gh api \
    --method PUT \
    "repos/$REPO/branches/$BRANCH/protection" \
    --input <(echo '{
      "required_status_checks": {
        "strict": true,
        "contexts": []
      },
      "enforce_admins": true,
      "required_pull_request_reviews": {
        "required_approving_review_count": 1
      },
      "restrictions": null,
      "allow_force_pushes": false,
      "allow_deletions": false,
      "block_creations": false
    }') >/dev/null

  echo "✔ Branch $BRANCH geschützt"
}

apply_protection main
apply_protection develop

#
# 4) Labels erstellen
#
echo "🏷️  Labels anlegen..."
gh label create "feature"        --color FFD700 --description "Neue Funktion"        --repo "$REPO" 2>/dev/null || true
gh label create "bug"            --color FF0000 --description "Fehler"               --repo "$REPO" 2>/dev/null || true
gh label create "documentation"  --color 1E90FF --description "Docs Änderungen"       --repo "$REPO" 2>/dev/null || true
gh label create "refactor"       --color 9370DB --description "Code Refactoring"     --repo "$REPO" 2>/dev/null || true
gh label create "wip"            --color 808080 --description "In Arbeit"            --repo "$REPO" 2>/dev/null || true
gh label create "release"        --color 32CD32 --description "Release relevant"     --repo "$REPO" 2>/dev/null || true
echo "✔ Labels fertig"

#
# 5) GitHub Project erstellen
#
echo "📋 Prüfe GitHub Project..."
PROJECT_ID=$(gh project list --owner "$OWNER" --format json | jq -r '.projects[] | select(.title=="'"$PROJECT_TITLE"'") | .id')

if [ -z "$PROJECT_ID" ]; then
  echo "🆕 Erstelle Project: $PROJECT_TITLE"
  gh project create --owner "$OWNER" --title "$PROJECT_TITLE"
else
  echo "✔ Project existiert ($PROJECT_ID)"
fi

#
# 6) Milestones automatisch anlegen
#
echo "🎯 Lege Milestones an..."
create_milestone() {
  local TITLE="$1"
  local DESC="$2"

  if gh api "repos/$REPO/milestones" | jq -r '.[].title' | grep -q "$TITLE"; then
    echo "✔ Milestone '$TITLE' existiert"
  else
    echo "🆕 Milestone: $TITLE"
    gh api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      "repos/$REPO/milestones" \
      -f title="$TITLE" \
      -f description="$DESC"
  fi
}

create_milestone "v0.1.0 – MVP" "Minimal Viable Product"
create_milestone "v0.2.0 – Core Features" "Produkte, Lager, Kunden"
create_milestone "v1.0.0 – Stable" "Stabile Produktionsversion"

#
# 7) Issue Templates + PR Templates
#
mkdir -p .github/ISSUE_TEMPLATE

echo "📝 Issue & PR Templates erstellen..."

cat <<EOF > .github/ISSUE_TEMPLATE/feature_request.md
name: Feature Request
description: Neue Funktion vorschlagen
title: "[Feature] "
labels: ["feature"]
body:
  - type: textarea
    id: beschreibung
    label: Beschreibung
EOF

cat <<EOF > .github/ISSUE_TEMPLATE/bug_report.md
name: Bug Report
description: Fehler melden
title: "[Bug] "
labels: ["bug"]
body:
  - type: textarea
    id: steps
    label: Reproduktion
EOF

cat <<EOF > .github/pull_request_template.md
## 🔥 Änderungen
- 

## 📦 Kontext
- Issue: #

## ✔️ Checklist
- [ ] Tests laufen
- [ ] Keine Lint Fehler
- [ ] Dokumentation aktualisiert
EOF

echo "✔ Templates erstellt"

#
# 8) Release-Drafter
#
echo "📦 Release-Drafter Workflow erstellen..."
mkdir -p .github/workflows

cat <<EOF > .github/workflows/release-drafter.yml
name: Release Drafter
on:
  push:
    branches: [ main ]

jobs:
  update_release_draft:
    runs-on: ubuntu-latest
    steps:
      - uses: release-drafter/release-drafter@v6
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
EOF

#
# 9) Auto-Changelog
#
echo "📜 CHANGELOG Setup..."
cat <<EOF > .github/workflows/changelog.yml
name: Changelog
on:
  release:
    types: [published]

jobs:
  changelog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Generate Changelog
        run: |
          git fetch --tags
          npx auto-changelog --commit-limit false --template keepachangelog
      - name: Commit Changelog
        run: |
          git config user.email "actions@github.com"
          git config user.name "GitHub Actions"
          git add CHANGELOG.md
          git commit -m "docs: update changelog" || true
          git push
EOF

#
# 10) CI Workflow (Flutter)
#
echo "⚙️ CI Workflow erstellen..."
cat <<EOF > .github/workflows/ci.yaml
name: CI
on:
  pull_request:
    branches: [ main, develop ]
jobs:
  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Flutter Pub Get
        run: flutter pub get
      - name: Flutter Analyze
        run: flutter analyze
      - name: Flutter Test
        run: flutter test
EOF

#
# 11) Commit alles
#
echo "📦 Committe generierte Dateien..."
git add .
git commit -m "chore: enterprise GitHub setup (milestones, release-drafter, changelog, ci, templates)" || true
git push

echo "🎉 Komplettes Enterprise Setup fertig!"
