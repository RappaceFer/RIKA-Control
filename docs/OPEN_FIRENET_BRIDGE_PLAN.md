# RIKA Control Bridge — intégration Open Firenet

> Proposition d'architecture, **aucun changement physique et aucune commande autonome activée**.
> Ne pas flasher ni brancher une carte ESP32-S3 tant que la référence exacte de la carte, le port USB natif et le firmware de la carte principale RIKA ne sont pas confirmés.

## Dépôts / licences

- Application Android Flutter autonome : `RappaceFer/RIKA-Control`, MIT, client de l'API HTTP locale.
- Firmware USB : créer un **fork GitHub** de `openfirenet/open-firenet` dans le compte RappaceFer ; conserver l'historique Git, les mentions d'auteur et l'**AGPL-3.0-or-later**.
- Ne pas recopier des fichiers AGPL dans la base MIT de l'APK. Communication au moyen du protocole REST documenté uniquement.
- Afficher une mention claire « basé sur Open Firenet » et un lien vers le code source complet du firmware dérivé. Pas de don ni pub dans l'APK.

## Comportement cible

1. Lire l'état et la sonde RIKA via `GET /api/state` depuis l'ESP32.
2. Contrôle Smart indépendant : puissance 30 % dans un mode compatible, agenda hebdomadaire, consigne et hystérésis, temporisations anti-cycles.
3. Faire le pilotage normal au travers de l'API locale, **sans contourner aucune sécurité du poêle**, avec validation de la révision/état réel et reprise manuelle prioritaire.
4. Ne pas répéter les ordres au démarrage ; pas de démarrage automatique tant que les conditions de sécurité et les capacités du firmware ne sont pas démontrées.
5. Déconnexion sonde, anomalie USB/Wi-Fi, redémarrage ou erreur : mode sûr défini et testé ; ne jamais promettre un arrêt thermique si le lien est perdu.
6. Enregistrement local des états et de l'historique, sans dépendre du VPS ni du téléphone.

## Séquence de validation

- **Phase A : identification** de la carte ESP32-S3 (photo face/dos, connecteur USB natif GPIO19/20) et de la version firmware *carte principale* du DOMO (pas seulement l'écran tactile).
- **Phase B : banc d'essai sans poêle** : compilation du fork, test interface écran et tests logiques simulés ; conserver la clé FIRENET officielle.
- **Phase C : lecture USB seule sous surveillance**, après vérification de compatibilité ; confirmer sonde, mode, puissance, états et alarmes.
- **Phase D : commande unique sous supervision**, comparer la valeur demandée à la valeur appliquée et au comportement réel. Tester d'abord les réglages sans risque, puis les commandes de marche/arrêt normales.
- **Phase E : régulation autonome Smart** après validation des délais anti-cycles, reprise en main, panne de capteur et arrêt de secours.

## API Open Firenet documentée

- `GET /api/state` : poêle, sonde, mesures, états.
- `GET /api/controls` et `POST /api/controls` : commandes.
- `GET /api/schedule` et `POST /api/schedule` : planning.

Référence : https://github.com/openfirenet/open-firenet/blob/main/README.md
Schéma : https://github.com/openfirenet/open-firenet/blob/main/openapi.yaml

## Risques identifiés

- Open Firenet annonce les versions 2.25 et antérieures comme non testées. En octobre 2026 un cas 2.25 a montré un protocole numérique différent ; la compatibilité exacte du DOMO doit être examinée avant flash/branchement.
- Le firmware Open Firenet gère l'écran d'une **T-Dongle-S3** ; l'écran de la **T-Display-S3** et les variantes NerdMiner ne doivent pas être présumés compatibles sans adaptation des broches.
- Pas d'exposition de l'API HTTP du bridge sur Internet ; sécuriser le réseau et prévoir une authentification pour les commandes distantes.
- La résolution effective de la sonde et les limites de 0,1 °C doivent être mesurées ; ne pas inventer une précision de régulation.
- Si on copie/modifie les sources Open Firenet, leur AGPL impose la publication du code du firmware dérivé, conformément à la licence.

**Statut : architecture documentée, fork et tests sur matériel pas encore faits.**
