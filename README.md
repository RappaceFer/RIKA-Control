# RIKA Control — v0.6.0

Application Android communautaire, indépendante de RIKA et de Netatmo. Interface Flutter noir/orange. Aucune publicité, aucun paiement ni don dans l'application. Licence MIT du dépôt conservée.

## Chauffage
Connexion au portail officiel dans une WebView à domaines HTTPS autorisés. Pas de mot de passe copié dans Dart, les journaux ou les fichiers du projet. Découverte du poêle du compte, sans identifiant personnel codé en dur.

Commandes explicites avec confirmation : marche/arrêt normal, Manuel/Automatique/Confort, puissance, MultiAir et consigne par pas de 0,1 °C. Une consigne de 22.2 est envoyée comme telle, sans arrondi local. Le retour FIRENET et la révision acquittée sont distingués de la valeur demandée. Ni HTTP 200 ni un affichage décimal ne prouvent la précision physique de régulation.

Lecture fraîche avant chaque POST, préservation des autres paramètres, aucun renvoi automatique. Pause anti-double-clic de 5 s et attente d'acquittement pour les commandes suivantes, sauf arrêt normal. Deux relectures ciblées à 5 et 15 s après l'envoi ; lecture périodique à 60 s, actualisation manuelle espacée de 15 s. Les réponses 429 et Retry-After suspendent les requêtes. Aucune boucle de marche/arrêt pour simuler une précision supérieure.

## Planning natif
Onglet Planning : lundi à dimanche, deux plages par jour, copie lundi→vendredi et samedi→dimanche, consigne réduite, activation des horaires en Confort. L'envoi remplace les 14 plages après confirmation ; il ne change pas ON/OFF ni la consigne Confort actuelle. Le mode et les horaires peuvent néanmoins changer immédiatement le fonctionnement d'un poêle déjà en marche.

Le programme utilise l'horloge interne du poêle et une semaine récurrente. Vérifier date/heure du poêle. Pas de température différente à chaque plage, pas de basculement automatique de profil à une date future. Des profils nommés (Habituel, Vacances…) peuvent être sauvegardés localement et chargés manuellement. Les créneaux traversant minuit sont refusés dans cette version. Les plages qui se chevauchent sont refusées.

## Historique local
Onglet Historique : fenêtres 24 h, 7 j et 30 j ; courbes de température ambiante, consigne relue et puissance demandée ; temps de chauffe observé et couverture temporelle. Collecte uniquement au premier plan. Pas de reconstitution des périodes où l'app est fermée, pas d'import rétroactif du cloud. Une interruption supérieure à 150 s coupe les courbes et les compteurs. Le temps de chauffe est une estimation à partir d'observations successives de l'état En chauffe, pas une mesure exhaustive. Aucune conversion fictive en kWh ou kg.

Stockage privé par poêle, sans cookie ni JSON technique brut ; historique borné à 35 jours au chargement. Profils et historique restent sur ce téléphone et peuvent être perdus à la désinstallation. Aucun serveur de télémétrie.

## Validation
Le workflow lance l'analyse Flutter, les tests unitaires/widget, les tests JavaScript simulés puis la construction de l'APK debug. Les tests ne contactent jamais un poêle. Une compilation réussie ne remplace pas les essais réels des commandes, du planning et de la précision sur chaque modèle.

## Références d'interopérabilité
- RIKA Touch Display 2.16 : https://rika.ams3.cdn.digitaloceanspaces.com/rika-web/download/archives/TouchDisplay_V2.16_190923_185748.pdf (pages 5–6 : modes et deux plages par jour).
- ioBroker FIRENET : https://github.com/iobroker-community-adapters/ioBroker.rika-firenet (lecture/écriture JSON, recommandation de polling périodique >= 1 min).
- Netatmo : https://static.netatmo.com/therm/manual1_fr-FR.pdf (mesure +/-0,1 °C, incrément de consigne 0,5 °C pour le modèle documenté).
- Open Firenet : https://openfirenet.github.io/api.html (boîtier alternatif, consigne entière ; ne prouve pas à lui seul la limite de l'API officielle).

Ne pas changer la calibration de sonde pour masquer un arrondi, ni les sécurités ou paramètres de combustion. Un contrôleur externe de précision demanderait une sonde adéquate, une interface compatible validée et une exécution continue ; ce n'est pas implémenté ici.
