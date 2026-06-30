#!/bin/bash
# Dfg Browser - GitHub setup
# Запусти в корне проекта

echo "=== Dfg Browser GitHub Setup ==="
read -p "GitHub username: " USER
read -p "Repo name [dfg-browser-ios]: " REPO
REPO=${REPO:-dfg-browser-ios}

git init
git add .
git commit -m "Dfg Browser 1.1 - Chrome Web Store real"
git branch -M main
git remote add origin https://github.com/$USER/$REPO.git
git push -u origin main

echo ""
echo "✅ Залито!"
echo "Открой: https://github.com/$USER/$REPO/actions"
echo "Нажми Run workflow → через 5 мин скачай IPA в Artifacts"
