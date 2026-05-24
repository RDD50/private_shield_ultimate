# PrivateShield Ultimate

APK Android Flutter pour diagnostic sécurité, vie privée et durcissement du téléphone.

## Fonctions incluses

- Score global de sécurité
- Sous-scores : système, réseau, radio, permissions, vie privée, comportement
- Scan réseau local basique
- Scan Bluetooth BLE
- Scan Wi-Fi visible selon permissions Android
- Détection de SSID ressemblants suspects
- Détection de réseaux ouverts
- Checklist de durcissement Android
- Mode voyage sécurisé
- Mode anti-tracking via analyse radio et checklist
- Boutons vers réglages Android sensibles
- Historique local des scans
- Export JSON local
- Build APK automatique via GitHub Actions

## Limites assumées

PrivateShield Ultimate ne remplace pas un antivirus, un MDM ou un outil root. Android bloque certaines informations pour protéger la vie privée. L'app guide donc l'utilisateur vers les réglages système quand une vérification automatique n'est pas possible.

## Création depuis Android avec Termux

```bash
git init
git add .
git commit -m "Initial PrivateShield Ultimate APK"
git branch -M main
git remote add origin https://github.com/TON_COMPTE/private_shield_ultimate.git
git push -u origin main
```

Ensuite :

1. Ouvre ton dépôt GitHub.
2. Va dans l'onglet **Actions**.
3. Lance **Build Android APK** si le build ne part pas automatiquement.
4. Télécharge l'artefact **PrivateShield-Ultimate-debug-apk**.
5. Installe `app-debug.apk` sur Android.

## Pourquoi le workflow lance flutter create

Le dépôt contient le code Flutter et le manifest Android personnalisé. GitHub Actions génère les fichiers Android natifs avec `flutter create`, puis remplace le manifest par celui du projet. Cela évite de gérer un dossier Android complet depuis un téléphone.
