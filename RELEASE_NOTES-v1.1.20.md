# Notes de version — v1.1.20-ventoy-sort

Release stable prévue pour le fork **ventoy-fork**, basée sur Ventoy upstream v1.1.17.

## Correctifs et validation

- Corrige le débordement de `1.1.20-ventoy-sort` dans la GUI Linux : fenêtre Qt élargie et taille de police ajustée au texte, cadres GTK élargis et version WebUI non coupée.
- Rend le projet Qt construisible hors de la machine d’origine en remplaçant les chemins d’inclusion absolus par des chemins relatifs.
- Vérifie les dimensions déclarées pour Qt, GTK et WebUI, puis compile la vraie fenêtre Qt, la rend hors écran et mesure ses libellés de version.
- Le workflow GitHub Actions construira le ZIP Windows prêt à l’emploi à partir de la baseline officielle Ventoy 1.1.17, puis le vérifiera avant de l’ajouter à la release. Le paquet Windows ne contient pas l’application GUI Linux ; les corrections d’affichage portent sur les sources Linux du dépôt.

## Secure Boot

Le paquet Windows est signé avec la clé MOK configurée dans les secrets du dépôt. Pour activer Secure Boot, enrôler le certificat public `ventoy-sort-MOK.cer` fourni à côté du paquet, selon [`PROCEDURE-SECURE-BOOT.md`](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md).
