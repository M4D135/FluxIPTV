# Feuille de route FLUX IPTV

## Intégré dans les sources 0.8.5

- Catalogue complet, cinq boîtiers maximum, coffrets séries articulés.
- Cinéma / vidéoclub / salon, six thèmes indépendants, fonds précalculés.
- Aperçu sur le verso, délai 3/5/10 s, plein écran explicite.
- Navigation contextuelle Haut / Bas / Retour, description à sources identifiées.
- Favoris avec choix des listes et confirmation d’enregistrement.
- Navigation générale retirée pendant toute lecture ; commandes flottantes compactes avec masquage automatique.
- Liquid Glass natif clair pour les commandes vidéo, compilation Xcode 26 et contrôle des SDK dans Actions.
- Bandes-annonces YouTube intégrées sur macOS/iOS, même lecteur entre miniature et plein écran ; URL vidéo directes natives sur les trois plateformes.
- Extraction des métadonnées de bande-annonce tolérant un premier champ vide, nul ou invalide.

## Qualification automatisée

- GitHub Actions compile macOS, iOS Simulator et tvOS Simulator, exécute les tests du cœur et vérifie les 18 fonds et le projet généré.
- Une vraie WKWebView sur macOS est exercée avec un fournisseur IFrame local pour vérifier le cycle de vie du lecteur et les commandes.
- Les applications compilées, les sources du commit exact et leurs empreintes sont disponibles dans les artefacts de chaque exécution réussie. Le statut de l’exécution reste la référence pour chaque version.

## Validation restant à faire sur Apple

- Qualification de l’installateur Mac et de la distribution sur appareils physiques.
- Siri Remote physique, focus des feuilles et de la barre d’actions.
- Lecture HLS/MP4 et cas de refus de capture ; arrêt de l’aperçu avant la lecture.
- Passage souris / clavier / trackpad, catalogue volumineux et mémoire réelle.
- Identification de fiches externes avec un catalogue réel, réseau lent ou coupé.
- Lecture YouTube réelle, refus d’intégration et rendu de Liquid Glass sur chaque appareil.

## Développements ultérieurs

- EPG/XMLTV et programmes présent/suivant.
- Agrégation de reprise des épisodes dans la carte d’un coffret.
- Sélection des pistes VLC et qualification des cibles mobiles.
- Distribution signée, icônes et préparation d’une livraison App Store.

Le détail de validation de chaque version reste dans son rapport ; une tâche implémentée n’est pas assimilée à une qualification sur appareil.
