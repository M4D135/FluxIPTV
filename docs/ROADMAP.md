# Feuille de route FLUX IPTV

## Intégré dans les sources 0.8.9 — build 34

- Filtre des chaînes par pays détecté dans le préfixe des catégories, avec conservation des catégories non identifiées.
- Mémoire de navigation par source et par section : pays, catégorie, recherches, favoris, page et sélection ; restauration après relance sans démarrer la lecture.
- Corrections de focus après recherche vide ou remplacement de recherche, avec vérification de la sélection logique et du focus natif.
- Marge supérieure des saisons adaptée au zoom et au déplacement de la carte sélectionnée.

- Sélection d’un film : fiche plein écran avec description lisible, bande-annonce, lecture et favoris. La scène de boîtes manipulables et les voisins ont été retirés.
- Sélection d’une série : rayon des saisons, puis fiche de la saison et choix des épisodes avec conservation de la reprise.
- Apple TV : grandes entrées TV, Films, Séries et Recherche ; catégories horizontales et grandes vignettes de chaînes 16:9.
- Accueil « Charger une liste » au démarrage sans source ; conservation des listes déjà enregistrées.
- Cinéma / vidéoclub / salon, six ambiances par espace, 18 fonds précalculés conservés.
- Aperçu TV unique et muet dans la vignette sélectionnée ; délai 1/3/5/10 s séparé de celui des bandes-annonces.
- Bandes-annonces dans l’application : lecteur YouTube embarqué sur Mac/iOS, résolution locale de formats publics et AVPlayer sur tvOS, vidéos directes natives sur les trois plateformes. Aucun QR code ni transfert sur iPhone.
- Même session vidéo entre la fiche et le plein écran ; arrêt avant la lecture principale. Les refus du fournisseur sont affichés dans l’app.
- Favoris avec choix des listes et confirmation d’enregistrement ; navigation générale retirée pendant la lecture ; commandes compactes à masquage automatique.
- Rendu tvOS allégé : surfaces sombres sans flou, décor décodé à une résolution bornée, grilles paresseuses, catalogue démonté pendant la fiche. Animations de focus et de transition conservées.
- Projet Xcode Apple TV dédié et lancement Release optimisé ; projet partagé pour Mac, iPhone/iPad et Apple TV.

## Qualification automatisée

- GitHub Actions compile macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 Release, exécute les tests du cœur et vérifie les 18 fonds et les deux projets générés.
- Le contrôle syntaxique examine aussi les branches conditionnelles des plateformes et les déclarations SwiftUI.
- Une vraie WKWebView sur macOS est exercée avec un fournisseur IFrame local pour vérifier le cycle de vie du lecteur, les commandes et les reprises après erreur.
- Un vrai AVPlayer est exercé avec une vidéo locale pour le délai, l’annulation et le nettoyage de l’aperçu TV.
- Les captures SwiftUI Mac et Apple TV contrôlent les fiches plein écran, les catégories, l’accueil, le focus natif et l’absence de scène SceneKit dans la présentation.
- Les applications compilées, les sources du commit exact et leurs empreintes sont disponibles dans les artefacts de chaque exécution réussie. Le statut de l’exécution reste la référence pour chaque version.

## Validation restant à faire sur Apple

- Qualification de l’installateur Mac et de la distribution sur appareils physiques.
- Siri Remote physique, focus des feuilles et de la barre d’actions.
- Lecture HLS/MP4 et cas de refus de capture ; arrêt de l’aperçu avant la lecture.
- Passage souris / clavier / trackpad, catalogue volumineux et mémoire réelle.
- Catalogue fournisseur réel, réseau lent ou coupé et disponibilité des métadonnées.
- Lecture YouTube réelle, refus d’intégration et rendu de Liquid Glass sur chaque appareil.

## Développements ultérieurs

- EPG/XMLTV et programmes présent/suivant.
- Agrégation de reprise des épisodes dans la carte d’un coffret.
- Sélection des pistes VLC et qualification des cibles mobiles.
- Distribution signée, icônes et préparation d’une livraison App Store.

Le détail de validation de chaque version reste dans son rapport ; une tâche implémentée n’est pas assimilée à une qualification sur appareil.
