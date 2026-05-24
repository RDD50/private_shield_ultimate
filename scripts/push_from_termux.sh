#!/data/data/com.termux/files/usr/bin/bash
set -e

git init
git add .
git commit -m "Initial PrivateShield Ultimate APK"
git branch -M main

echo "Ajoute maintenant ton depot distant :"
echo "git remote add origin https://github.com/TON_COMPTE/private_shield_ultimate.git"
echo "git push -u origin main"
