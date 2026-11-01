# RIKA Control Smart — ESP32-S3 (prototype autonome, **simulation**)

**Cible matérielle provisoire : LILYGO T-Display-S3 standard 1,9", ST7789 170×320 I8080, sans AMOLED.** Une carte « NerdMiner ESP32-S3 » peut être d’une autre variante : confirmer avec une photo et le marquage de la carte **avant de flasher**.

## État de ce firmware V0.1

- Écran noir/orange, température ambiante et consigne ; boutons GPIO0 (−0,1 °C) et GPIO14 (+0,1 °C).
- Température et humidité depuis un capteur **SHT31 I²C externe** à l’adresse 0x44. Bus Qwiic/STEMMA QT de la carte standard : SDA GPIO18 et SCL GPIO17 (alimentation 3,3 V).
- Exemple de planning hebdomadaire 2 plages par jour, défini dans `include/control_logic.h`.
- Régulation locale : arrêt de demande à la consigne, reprise possible à consigne −0,8 °C avec délai anti-redémarrage 20 min. **Ces valeurs sont seulement destinées aux essais en simulation**.
- Consigne conservée dans NVS (Preferences) après 3 secondes d’inactivité.
- Heure locale Europe/Paris par NTP (nécessite Wi-Fi configuré). Si l’heure ou la sonde manque : aucune demande de chauffe.
- API locale **en lecture seule** : `GET http://IP_DE_L_ESP32/api/status`, statut JSON sans mot de passe. À utiliser uniquement sur réseau local fiable, **jamais exposer sur Internet**.

### ⚠️ Très important : aucun pilotage physique pour l’instant

**Aucun GPIO de relais n’est configuré. Ce firmware n’actionne ni le poêle ni son entrée thermostat, même si l’écran affiche « CHAUFFE DEMANDÉE ».** Il ne doit pas être considéré comme un dispositif de sécurité, une régulation validée ou un remplacement de thermostat certifié.

L’objectif est de valider l’écran, la carte précise, la sonde, le planning, le comportement de la logique et la mise à disposition des données pour l’APK. Ensuite seulement : adapter un contact sec **galvaniquement isolé**, avec validation par un installateur RIKA du connecteur, des tensions, de l’état sûr à la mise hors tension et de la priorité du thermostat externe. Ne jamais injecter 3,3 V ou 5 V dans l’entrée du poêle. L’appareil conserve toutes ses sécurités d’origine.

## Installation sur PC Windows (après identification précise du matériel)

1. Installer VS Code et l’extension PlatformIO, puis ouvrir **ce dossier**.
2. Si souhaité pour NTP/API locale, copier `include/network_secrets.example.h` vers `include/network_secrets.h`, et indiquer ton SSID et mot de passe **uniquement sur ton PC**. Le fichier est ignoré par Git et ne doit pas être publié.
3. Installer un SHT31 3,3 V sur le connecteur Qwiic, puis compiler l’environnement `lilygo_t_display_s3`.
4. Avant de téléverser, faire une copie du firmware Bitcoin si tu veux pouvoir le restaurer ; flasher écrasera l’ancien programme. Confirmer la référence de la carte.
5. Après flash, vérifier à l’écran la température, les boutons et les états « SIMULATION » et « AUCUNE SORTIE VERS LE POÊLE ».
6. Si Wi-Fi configuré, lire l’adresse IP sur le moniteur série et tester `/api/status` depuis le réseau local.

La configuration par défaut n’a **aucun identifiant Wi-Fi**, donc pas d’horloge synchronisée ni de chauffe autorisée en simulation. C’est volontairement conservateur.

## Intégration prévue à RIKA Control APK

L’APK pourra lire le JSON local via une adresse IP ou mDNS après validation de la connexion. On ajoutera ensuite une authentification robuste et une synchronisation des réglages, sans ouvrir de port sur la box. La clé FIRENET peut rester branchée et fonctionner en parallèle : **elle n’est pas modifiée**.

## Build automatique

Le workflow GitHub Actions `esp32-firmware.yml` vérifie le moteur de décision en C++ natif et compile un `firmware.bin` de démonstration. La compilation n’atteste pas la compatibilité exacte avec ta variante de carte. **Ne pas flasher tant que la carte n’a pas été identifiée**.

## Références

- [LILYGO T-Display-S3 — broches, connecteur Qwiic et écran](https://wiki.lilygo.cc/products/t-display-series/t-display-s3/)
- [PlatformIO board `lilygo-t-display-s3`](https://docs.platformio.org/en/stable/boards/espressif32/lilygo-t-display-s3.html)
- [Arduino_GFX — déclaration de la T-Display-S3](https://github.com/moononournation/Arduino_GFX/wiki/Dev-Device-Declaration)
