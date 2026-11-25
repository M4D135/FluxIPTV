# FLUX IPTV 0.8.7 — Rayons de saisons, boîtiers stables et projet Apple TV

Version native SwiftUI pour macOS, iOS et tvOS.

**Nouveautés 0.8.7 :** une série ouvre son rayon de saisons ; choisir une saison présente ses épisodes dans un grand boîtier. La caméra et les voisins restent fixes pendant la manipulation. Un Dock garde les actions visibles, la recherche rejoint TV/Films/Séries sous une grande icône loupe, et les descriptions utilisent uniquement le synopsis IPTV. Un projet Xcode dédié à Apple TV évite de sélectionner par erreur le schéma Mac.

Les DVD restent utilisés à partir de 2000, les VHS avant 2000. La lecture des épisodes corrige un défaut de récupération de l’extension fournie par le serveur ; les erreurs du lecteur Apple et le choix d’une adresse pour VLC externe sont plus explicites.

La TV dispose d’une navigation dédiée : catégories à gauche, recherche et chaînes compactes, aperçu automatique dans une vignette et délai **1 / 3 / 5 / 10 secondes propre à la TV**. Les trois espaces partagent des modules de navigation Liquid Glass sur les systèmes 26 compatibles. Les 18 décors sont reconstruits en **3840 × 2160**, avec des architectures et des meubles distincts selon le thème.

Les acquis de 0.8.5 sont conservés : lecture sans bandeau de catalogue, commandes flottantes qui se masquent, lecteur officiel YouTube sur macOS/iOS et session unique entre miniature et plein écran.

## Trois espaces, six thèmes chacun

| Contenu | Espace | Présentation |
|---|---|---|
| Films | Cinéma | Hall, salle, fauteuils, éclairage de séance |
| Séries | Vidéoclub | Rayons de séries, puis saisons et épisodes |
| Direct | Salon TV | Canapé, meuble TV, lumières domestiques |

Les six thèmes restent disponibles : Néo 80–90, Cinéma de minuit, Salon 70, Palace Art déco, Scandinave et Futur néon. Dans **Réglages → Interface**, chacun des trois espaces possède son propre choix. Les anciennes préférences du vidéoclub sont migrées vers Films et Séries sans écraser un réglage déjà choisi.

Les 18 fonds 4K sont fabriqués par un script Blender à partir de géométrie et de matériaux procéduraux originaux, puis précalculés en JPEG 3840 × 2160. Les salons ont chacun une implantation : loft de briques et métal, penthouse vitré de nuit, salon 70 en U, arches Art déco et laiton, chêne clair et shoji, pavillon futuriste à nervures facettées. Les cinémas et vidéoclubs varient également leurs structures et leurs îlots. Le rendu utilise Cycles et le débruitage Intel Open Image Denoise. Il ne s’agit pas du runtime GPU FERRO. Aucun calcul de pièce 3D continu n’est exécuté dans l’application. Les boîtes interactives utilisent SceneKit/Metal.

Le script reproductible, le manifeste et la planche des décors sont dans `scripts/rooms/`. Les images de cette planche sont les fonds embarqués, pas des captures d’écran de l’application.

## Piloter une boîte

La grille conserve le catalogue complet, sous forme de rangées rapprochées. Le titre choisi avance hors du rayon et occupe presque toute la hauteur utile. Jusqu’à quatre voisins restent derrière lui : leur position, leur taille projetée et la caméra ne changent pas pendant la rotation ou l’ouverture. Le cadrage du seul boîtier tenu s’adapte à sa pose, avec une séparation de profondeur qui évite les intersections. Le format est déterminé par l’année des métadonnées : **VHS avant 2000, DVD dès 2000** ; une année absente utilise un DVD.

| Contexte | Commande | Résultat |
|---|---|---|
| Grille de films | Clic / Valider | Prendre la boîte |
| Grille de séries | Clic / Valider | Entrer dans le rayon des saisons |
| Grille | Appui long | Choisir les listes de favoris |
| Boîte tenue | Gauche / Droite | Tourner la boîte |
| Boîte tenue | Deux appuis rapides dans la même direction | Titre précédent / suivant |
| Boîte tenue | Haut | Sélectionner le widget d’aperçu, en présentant le verso |
| Aperçu sélectionné | Valider | Bande-annonce en plein écran |
| Aperçu sélectionné | Haut | Sélectionner le bouton de lecture au-dessus |
| Bouton de lecture | Valider | Lire/reprendre le film ou l’épisode indiqué |
| Boîte tenue, quel que soit le bouton sélectionné | Lecture/Pause | Lire directement le film ou l’épisode choisi |
| Boîte ou aperçu | Bas | Sélectionner Reposer, à gauche dans la barre inférieure |
| Dock inférieur | Gauche / Droite, puis Valider | Choisir une action visible, de Reposer à Favoris |
| Boîte de film tenue | Retour / Menu | Reposer et retrouver le catalogue |
| Rayon des saisons | Directions, puis Valider | Choisir une saison et ouvrir ses épisodes |
| Saison ouverte | Reposer / Retour / Menu | Retrouver le rayon de la série |
| Rayon des saisons | Retour / Menu | Retrouver le catalogue des séries |
| Choix d’un épisode | Gauche / Droite, puis Valider | Choisir puis regarder ; les pages suivent automatiquement |
| Saison ou épisode | Haut / Bas | Sélectionner l’aperçu / les commandes inférieures |
| Bande-annonce plein écran | Retour | Retrouver la boîte, à la même position de lecture |
| Film plein écran | Retour | Arrêter la lecture et retrouver la boîte |

Le Dock est centré, avec icônes et titres visibles sans menu « … ». Ses boutons se soulèvent au survol ou au focus ; la réduction des animations désactive ce mouvement. Sur les petites largeurs, le Dock défile horizontalement sans comprimer les libellés. L’aide discrète sous la boîte change avec la sélection. Les flèches latérales restent cliquables pour changer de titre, sans faire partie du parcours normal des boutons inférieurs. Un double appui est reconnu entre 80 et 300 ms ; la répétition automatique des flèches du clavier est ignorée pendant l’inspection.

Sur Mac, glisser la souris ou deux doigts sur le trackpad tourne la boîte. **Dock → Manipuler** ajoute l’inclinaison verticale aux directions ; Valider termine ce mode. Sur Apple TV, les directions ordinaires tournent la boîte, et Manipuler autorise le geste continu sur le pavé tactile. Les contrôles de la vidéo YouTube restent utilisables.

Sur Mac : **Espace** correspond à Lecture/Pause, **Entrée** à Valider, **Échap** à Retour, **⌘F** ouvre la recherche et **⌘⇧F** bascule le plein écran natif. La réduction des animations et les contrastes système sont pris en compte.

## Verso : image, puis bande-annonce

Le cadre supérieur tente d’extraire une véritable image du film. Si le format ou le serveur le refuse, une image de la bande-annonce native ou le panorama fourni par l’IPTV peut servir de secours. Une miniature YouTube identifiée comme telle complète ces possibilités si aucune image du film ne peut être extraite. La provenance de l’image reste indiquée ; une jaquette n’est pas présentée comme une image extraite du film.

**Réglages → Interface → Aperçu au dos de la boîte** : démarrage automatique activable et délai **1, 3, 5 ou 10 secondes** (5 secondes par défaut). Le délai commence après la préparation de l’image fixe. La vidéo démarre en sourdine et reste dans son cadre, avec un fondu de 0,5 seconde vers le lecteur prêt à démarrer. Elle ne déplace pas la sélection et ne se lance pas en boucle. Une image manquante ne bloque plus une bande-annonce disponible. Sur une petite pochette, YouTube attend une ouverture explicite en grand pour conserver des commandes utilisables.

Un clic sur l’image, **Agrandir** ou l’action **Bande-annonce** ouvre le lecteur plein écran avec le son. Les commandes internes de YouTube restent utilisables dans le cadre. Retour retrouve la même boîte et remet l’aperçu en sourdine, en conservant la position du lecteur.

Sur macOS/iOS, les liens et identifiants YouTube valides sont lus avec le lecteur officiel dans une `WKWebView`. Le document transmet l’identité réelle de l’application, nécessaire notamment pour éviter l’erreur 153. Les erreurs de réseau, l’autoplay bloqué et les vidéos dont le propriétaire refuse l’intégration donnent un état explicite ; un lien YouTube reste proposé dans ce dernier cas. Aucun flux YouTube n’est extrait.

Les URL vidéo directes MP4, M4V, MOV et HLS restent prises en charge nativement selon leurs codecs. tvOS ne propose pas de WebView : les vidéos directes sont intégrées et YouTube conserve son ouverture explicite sur iPhone par QR code. Vimeo et Dailymotion restent des liens externes.

La bande-annonce continue pendant la rotation tant que son verso reste orienté vers le spectateur. Le retour au recto met le lecteur en pause sans le détruire ; revenir au verso reprend la même position si la lecture était active. Une pause manuelle ou une vidéo terminée reste respectée. Le couvercle du boîtier d’une saison conserve lui aussi son aperçu. Extraction, temporisation et lecteur s’arrêtent au changement de titre, à la fermeture de la boîte ou au passage en arrière-plan. Le passage à une vidéo plein écran attend l’annulation de l’extraction. Une seule vidéo d’aperçu est active. Lors de la lecture principale, le décor et la scène des boîtes sont retirés.

## Synopsis et lecture des épisodes

Le verso affiche exclusivement la description transmise par le fournisseur IPTV. Le sélecteur de sources et les requêtes Wikipédia/Allociné sont supprimés. Une description absente reste signalée comme telle.

Le décodeur d’épisodes vérifie séparément les champs d’extension du premier niveau et de `info` : une valeur vide ou invalide n’empêche plus de retenir une extension imbriquée valide. Le lecteur ne remplace pas arbitrairement une extension correctement déclarée. Les erreurs AVPlayer indiquent une cause de format, de décodage ou de réseau lorsque le SDK l’identifie, sans afficher d’adresse authentifiée. Sur Mac, si plusieurs adresses existent, l’ouverture volontaire dans VLC permet de choisir « Adresse 1 · MP4 », « Adresse 2 · MKV », etc. Aucun moteur supplémentaire n’est ajouté au Mac.

## Télévision : catégories et aperçu séparé

Le bandeau propose TV, Films, Séries et Recherche avec de grandes icônes et des surfaces de verre indépendantes. La loupe active la recherche dans l’espace courant ; ⌘F conserve le même comportement sur Mac. Les écrans larges affichent catégories, favoris et listes dans une colonne à gauche ; la recherche de catégories reste dans cette colonne. Sur une fenêtre étroite, un sélecteur compact conserve ces accès. La recherche de chaînes reste directement visible au-dessus du catalogue.

La sélection d’une chaîne soulève sa vignette et prépare un seul lecteur partagé par le catalogue. **Réglages → Interface → Aperçu des chaînes TV** permet d’activer l’aperçu et de choisir **1, 3, 5 ou 10 secondes**, avec **3 secondes par défaut**. Ce choix et son activation sont indépendants des bandes-annonces des films et séries, dont le délai par défaut reste 5 secondes.

L’aperçu démarre en sourdine, dans une vignette 16:9 ; une commande permet d’en activer le son. Il attend une sélection stable, annule l’attente quand la chaîne change et libère le lecteur précédent avant d’en créer un nouveau. Changement de catégorie, changement d’espace, arrière-plan, feuille de réglages et lecture principale arrêtent l’aperçu. Un flux incompatible ou inaccessible garde un état lisible et l’action Regarder disponible.

Sur Mac/iOS, un clic sélectionne la chaîne ; Regarder ou Valider lance la lecture principale. Sur Apple TV, le focus sélectionne et OK regarde. Gauche revient vers la colonne de catégories depuis le bord de la grille, et Droite rejoint la chaîne précédemment choisie. La pagination et l’indexation existantes évitent de construire des milliers de vues ou un lecteur par cellule. Aucun programme EPG n’est inventé.

## Lecture et commandes flottantes

La vidéo occupe la fenêtre entière. Le bandeau FLUX, les onglets et la télécommande latérale sont retirés de cette vue. Les commandes de lecture se limitent à un panneau centré de largeur bornée, avec une petite capsule supérieure pour Retour, le titre et Plein écran. Afficher les commandes ne redimensionne pas l’image.

Le panneau se masque après trois secondes de lecture sans interaction ; pointeur, toucher, clavier et télécommande le rappellent. Pause, chargement, erreur, réglages, déplacement du curseur ou VoiceOver le maintiennent visible. Les options Réduire la transparence et Réduire les animations sont respectées. Les pistes, sous-titres et réglages de volume restent accessibles depuis la roue dentée.

## Favoris et rayons de saisons

L’appui long sur une carte, l’étoile et l’action Favoris ouvrent la même feuille : cocher les listes, créer éventuellement une liste, puis **Enregistrer**. **Annuler** ne modifie rien. Un message confirme l’enregistrement. Les listes Films, Séries et Direct restent séparées.

Chaque série possède son rayon de saisons. Les numéros transmis par le fournisseur sont conservés et la saison 0 est identifiée comme Spéciaux. Choisir une saison présente les épisodes avec leurs miniatures ; les positions de reprise existantes sont conservées. Le filtre « À reprendre » du catalogue concerne les films ; il ne prétend pas agréger automatiquement l’historique de tous les épisodes d’une série.

## Installer

L’archive contient les sources et l’installateur Mac, pas un binaire Apple précompilé.

1. Sur Mac, quitter l’ancienne app et arrêter le lancement depuis Xcode.
2. Décompresser, puis ouvrir **Installer Flux IPTV.command**. L’installateur compile sur ce Mac et vérifie le démarrage ; cette vérification ne remplace pas un essai de lecture.
3. Vérifier **0.8.7** dans la barre FLUX. Les réglages se trouvent dans Interface.

Prérequis de déploiement : macOS 14, iOS 17 ou tvOS 17. Installer Xcode complet pour compiler ; les API de verre natif utilisent le SDK/OS 26 lorsqu’ils sont disponibles. Sur iPhone/iPad ou Apple TV, ouvrir `FluxIPTV.xcodeproj`, choisir **FluxIPTViOS** ou **FluxIPTVTV**, puis renseigner l’équipe de signature pour un appareil physique.

Le Mac garde AVPlayer natif ; le bouton VLC externe reste disponible pour les formats incompatibles. Les cibles iOS/tvOS conservent l’intégration VLC expérimentale de la base. Les identifiants d’application et les préférences existantes sont conservés. Lire `LISEZ-MOI INSTALLATION.txt` pour les détails de signature et de Trousseau.

## Ouvrir le projet Apple TV

Ouvrir **`FluxIPTV-AppleTV.xcodeproj`**, ou lancer **`Ouvrir Flux IPTV Apple TV.command`**. Le projet dédié contient uniquement la cible et le schéma **FluxIPTVTV**, avec les mêmes sources, ressources et dépendance VLC que la cible tvOS du projet partagé. Choisir ensuite une destination Apple TV et exécuter avec ⌘R.

« Mismatched platform » avec le schéma **FluxIPTV / My Mac** signifie que la destination ne correspond pas au schéma actif. Dans le projet partagé, choisir d’abord le schéma **FluxIPTVTV**, puis la destination Apple TV. Pour une Apple TV physique, renseigner son équipe dans **Signing & Capabilities** et jumeler l’appareil dans Xcode. Les détails sont dans [LISEZ-MOI APPLE TV.txt](<LISEZ-MOI APPLE TV.txt>) et la [documentation Apple](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## Validation

Le périmètre des vérifications de cette livraison est dans [docs/VALIDATION-0.8.7.md](docs/VALIDATION-0.8.7.md). Les tests unitaires du cœur ne démontrent ni la compilation des frameworks Apple, ni la fluidité réelle, ni la lecture des flux du fournisseur. Aucun EPG n’a été ajouté dans cette version.

## GitHub Actions et pack complet

Le dépôt complet est [M4D135/FluxIPTV](https://github.com/M4D135/FluxIPTV). Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) se lance à chaque push sur `main`, sur les branches de travail des trois univers, lors des pull requests ou à la demande.

Actions exécute les tests du cœur, vérifie les 18 décors et les deux projets générés, puis compile séparément macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 pour appareil. Les journaux et les résultats Xcode sont conservés même lorsqu’une compilation échoue. Une compilation réussie fournit une archive de l’application correspondante ; le build iOS et le build tvOS Simulator sont destinés aux simulateurs. Le build tvOS pour appareil n’est pas signé et exige la signature de votre équipe pour être installé. Le build Mac n’est ni signé pour distribution ni notarié.

Un job indépendant prépare le **pack complet des sources du commit exécuté**, avec empreinte SHA-256 et identifiant du commit. Il inclut les projets Xcode multiplateforme et Apple TV, l’installateur Mac, le lanceur Apple TV, les tests, la documentation et tous les décors. La présence de ce pack ne vaut pas validation des compilations : consulter les résultats de chaque job dans la même exécution. Voir [docs/CI.md](docs/CI.md) pour les téléchargements et la relance.

### Vérifications locales

```bash
swift test
bash scripts/check-state-declarations.sh
python3 scripts/rooms/verify_rooms.py
bash scripts/test-live-preview.sh
bash scripts/test-case-scene.sh
bash scripts/test-youtube-session.sh
bash scripts/test-keychain-interaction.sh
bash scripts/test-catalog-ui.sh
bash scripts/build-platforms.sh macOS
bash scripts/build-platforms.sh iOS
bash scripts/build-platforms.sh tvOS
bash scripts/build-platforms.sh tvOS-device
```

Les versions précédentes sont conservées dans [docs/HISTORIQUE.md](docs/HISTORIQUE.md). Leurs anciennes commandes et résultats de tests ne décrivent pas la version actuelle.
