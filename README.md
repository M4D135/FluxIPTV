# FLUX IPTV 0.8.9 — build 31 — Pays TV et filtres mémorisés

Application native SwiftUI pour macOS, iOS et tvOS.

**0.8.9 ajoute le filtre par pays aux chaînes TV et mémorise la navigation.** Les préfixes des catégories (`FR | Généralistes`, `[FR] Cinéma`, `ES - Deportes`, `UK | News`), les noms de pays et les drapeaux reconnus alimentent le menu **Tous les pays**. Choisir France conserve les catégories françaises et leurs chaînes. Les catégories sans pays reconnu restent accessibles dans **Pays non identifié**. La liste des pays vient du catalogue complet, même si la recherche ou les favoris ne donnent aucun résultat.

Le pays, la catégorie, la recherche, la recherche de catégories, la liste de favoris, le filtre À reprendre des films, la page et la dernière sélection sont mémorisés **par source et par section**. Revenir dans TV ou relancer l’application retrouve ce contexte sans lancer une chaîne automatiquement. Le changement de section et Retour conservent les filtres ; **Toutes les chaînes** réinitialise explicitement les filtres TV, et **Tous les pays** dans le sélecteur retire seulement la restriction de pays. Une catégorie ou une chaîne supprimée par le fournisseur est écartée lors du prochain chargement réussi.

**0.8.8 refond la consultation des films et séries :** sélectionner un film ouvre une fiche plein écran avec grand synopsis et bande-annonce. Une série ouvre son rayon de saisons, puis les épisodes de la saison choisie. La scène de boîtes manipulables et ses voisins ont été retirés.

Sur Apple TV, **TV, Films, Séries et Recherche** utilisent de grandes icônes avec un focus explicite. Les chaînes suivent une disposition horizontale : catégories au-dessus de grandes vignettes 16:9, aperçu dans la seule vignette active. Les décors FLUX restent visibles. Au premier démarrage sans source, **Charger une liste** propose Xtream Codes ou une URL M3U ; Mac et iOS acceptent aussi un fichier M3U.

Les animations de focus, d’apparition et de transition restent actives. tvOS utilise des surfaces sombres sans flou de fond, un décor précalculé décodé à une résolution bornée et un seul aperçu vidéo. L’option système Réduire les animations reste respectée. Ces changements réduisent le travail de rendu ; une mesure de fluidité sur appareil reste distincte d’une compilation réussie.

## Trois espaces, six thèmes chacun

| Contenu | Espace | Présentation |
|---|---|---|
| Films | Cinéma | Hall, salle, fauteuils, éclairage de séance |
| Séries | Vidéoclub | Rayons de séries, puis saisons et épisodes |
| Direct | Salon TV | Canapé, meuble TV, lumières domestiques |

Les six thèmes restent disponibles : Néo 80–90, Cinéma de minuit, Salon 70, Palace Art déco, Scandinave et Futur néon. Dans **Réglages → Interface**, chacun des trois espaces possède son propre choix. Les anciennes préférences du vidéoclub sont migrées vers Films et Séries sans écraser un réglage déjà choisi.

Les 18 fonds 4K sont fabriqués par un script Blender à partir de géométrie et de matériaux procéduraux originaux, puis précalculés en JPEG 3840 × 2160. Les salons ont chacun une implantation : loft de briques et métal, penthouse vitré de nuit, salon 70 en U, arches Art déco et laiton, chêne clair et shoji, pavillon futuriste à nervures facettées. Les cinémas et vidéoclubs varient également leurs structures et leurs îlots. Le rendu utilise Cycles et le débruitage Intel Open Image Denoise. Il ne s’agit pas du runtime GPU FERRO. Aucun calcul de pièce 3D continu n’est exécuté dans l’application. Le catalogue utilise des images et des transformations SwiftUI légères ; la fiche ne crée aucune scène SceneKit.

Le script reproductible, le manifeste et la planche des décors sont dans `scripts/rooms/`. Les images de cette planche sont les fonds embarqués, pas des captures d’écran de l’application.

## Navigation à la télécommande

La grille garde ses rangées rapprochées et ses décors. Seul l’élément qui possède le focus avance légèrement ; les autres cartes ne changent pas d’échelle. La présentation des jaquettes reste **VHS avant 2000, DVD dès 2000** (DVD si l’année manque).

| Écran | Commande | Résultat |
|---|---|---|
| Catalogue | Directions | Déplacer la sélection |
| Film | Valider | Ouvrir sa fiche plein écran |
| Série | Valider | Ouvrir le rayon de ses saisons |
| Saison | Valider | Afficher la fiche et les épisodes |
| Fiche | Directions, puis Valider | Lecture, bande-annonce, description complète, favoris ou retour |
| Fiche | Lecture/Pause | Lire le film ou l’épisode sélectionné |
| Épisodes | Gauche / Droite, puis Valider | Choisir et lire l’épisode |
| Bande-annonce plein écran | Lecture/Pause | Mettre en pause ou reprendre |
| Bande-annonce plein écran | Retour / Menu | Retrouver la fiche et la même session vidéo |
| Fiche | Retour / Menu | Retrouver la sélection dans le catalogue ou le rayon |
| Rayon des saisons | Retour / Menu | Revenir au catalogue des séries |
| Chaînes TV | Rester sur une vignette | Démarrer l’aperçu après le délai choisi |
| Chaînes TV | Valider | Regarder la chaîne en plein écran |
| Catalogue | Appui long | Ouvrir les favoris et listes |

La fiche présente les actions à leur place, sans rotation ni commande de titre précédent/suivant. Le synopsis utilise uniquement les métadonnées IPTV ; aucun enrichissement Wikipédia ou Allociné n’est demandé. La description complète dispose d’un écran lisible. Sur Mac, **Entrée** valide, **Échap** revient, **Espace** correspond à Lecture/Pause, **⌘F** ouvre la recherche et **⌘⇧F** bascule le lecteur plein écran.

## Bandes-annonces dans l’application

**Réglages → Interface → Bandes-annonces** : lecture automatique activable, délai **1, 3, 5 ou 10 secondes**, 5 secondes par défaut. L’aperçu démarre en sourdine. **Bande-annonce** agrandit la vidéo et active le son ; Retour retrouve la fiche. Le lecteur est conservé entre ces deux présentations et arrêté avant la lecture principale.

Les vidéos directes MP4, M4V, MOV et HLS sont lues nativement selon les codecs disponibles. Sur macOS/iOS, les liens YouTube valides utilisent le lecteur officiel embarqué dans une WKWebView. Sur tvOS, le paquet local `Vendor/YouTubeKit` résout les formats publics compatibles pour AVPlayer. Cette intégration non officielle peut être affectée par les changements YouTube et les restrictions réseau. La provenance et les licences du sous-ensemble sont embarquées dans le paquet.

La résolution tvOS ne possède ni compte, ni serveur intermédiaire, ni mécanisme de contournement d’une connexion, d’un contrôle d’âge ou d’une protection. Si la lecture publique est refusée ou aucun format compatible n’est disponible, la fiche affiche la raison. **Aucun QR code ni renvoi sur iPhone.** Une page web ne devient jamais une URL de flux par simple substitution. L’app ne diffuse pas le film pour fabriquer une miniature de sa fiche.

## Télévision : grandes vignettes et catégories

Sur Apple TV, les catégories réelles de la liste défilent horizontalement, avec **Favoris** et **Toutes les chaînes**. La recherche s’ouvre depuis la grande loupe de la navigation. Jusqu’à quatre vignettes occupent la largeur du téléviseur. Le panneau de catégories latéral reste disponible sur les grands écrans Mac/iPad.

L’aperçu TV a son propre réglage : **1 / 3 / 5 / 10 secondes**, 3 secondes par défaut, indépendant des bandes-annonces. Il attend une sélection stable, reste muet et s’arrête quand le focus quitte la vignette sur tvOS ou lors de la lecture principale. Une seule vignette crée un lecteur. Les logos, titres et catégories viennent du fournisseur ; aucun programme, horaire EPG ou niveau de progression n’est inventé.

Les catalogues restent paginés et leurs grilles paresseuses afin de ne pas monter des milliers de vues. Le décor conservé est une image statique précalculée. Sur tvOS, le décodage de ce décor est plafonné à 1920 pixels de large et son cache à 32 Mio ; les textes et contrôles restent rendus à la résolution de l’interface. Ce plafond ne réduit pas la résolution du film ou de la chaîne lus.

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
3. Vérifier **0.8.9** dans la barre FLUX et le **build 31** dans Réglages. Les réglages d’apparence se trouvent dans Interface.

Prérequis de déploiement : macOS 14, iOS 17 ou tvOS 17. Installer Xcode complet pour compiler ; le verre système natif est réservé aux contrôles Mac/iOS compatibles ; tvOS privilégie des surfaces sombres légères. Sur iPhone/iPad ou Apple TV, ouvrir `FluxIPTV.xcodeproj`, choisir **FluxIPTViOS** ou **FluxIPTVTV**, puis renseigner l’équipe de signature pour un appareil physique.

Le Mac garde AVPlayer natif ; le bouton VLC externe reste disponible pour les formats incompatibles. Les cibles iOS/tvOS conservent l’intégration VLC expérimentale de la base. Les identifiants d’application et les préférences existantes sont conservés. Lire `LISEZ-MOI INSTALLATION.txt` pour les détails de signature et de Trousseau.

## Ouvrir le projet Apple TV

Ouvrir **`FluxIPTV-AppleTV.xcodeproj`**, ou lancer **`Ouvrir Flux IPTV Apple TV.command`**. Le projet dédié contient uniquement la cible et le schéma **FluxIPTVTV**, avec les mêmes sources, ressources, dépendance VLC et paquet local YouTubeKit que la cible tvOS du projet partagé. Choisir ensuite une destination Apple TV et exécuter avec ⌘R. Le schéma lance par défaut la configuration Release optimisée, sans débogueur ; Debug reste disponible pour le développement.

« Mismatched platform » avec le schéma **FluxIPTV / My Mac** signifie que la destination ne correspond pas au schéma actif. Dans le projet partagé, choisir d’abord le schéma **FluxIPTVTV**, puis la destination Apple TV. Pour une Apple TV physique, renseigner son équipe dans **Signing & Capabilities** et jumeler l’appareil dans Xcode. Les détails sont dans [LISEZ-MOI APPLE TV.txt](<LISEZ-MOI APPLE TV.txt>) et la [documentation Apple](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## Validation

Le périmètre des vérifications de cette livraison est dans [docs/VALIDATION-0.8.9.md](docs/VALIDATION-0.8.9.md). Le build 31 réunit les filtres par pays et leur mémoire avec les dernières corrections du focus natif de recherche, du sélecteur de pays et de la grille Apple TV. Les tests unitaires du cœur ne démontrent ni la compilation des frameworks Apple, ni la fluidité réelle, ni la lecture des flux du fournisseur. Aucun EPG n’a été ajouté dans cette version.

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
bash scripts/test-tvos-catalog-ui.sh
bash scripts/test-native-youtube.sh --live
bash scripts/test-youtube-session.sh
bash scripts/test-keychain-interaction.sh
bash scripts/check-keychain-platform.sh tvOS
bash scripts/check-keychain-platform.sh tvOS-device
bash scripts/check-keychain-platform.sh iOS
bash scripts/test-catalog-ui.sh
bash scripts/build-platforms.sh macOS
bash scripts/build-platforms.sh iOS
bash scripts/build-platforms.sh tvOS
bash scripts/build-platforms.sh tvOS-device
```

Les versions précédentes sont conservées dans [docs/HISTORIQUE.md](docs/HISTORIQUE.md). Leurs anciennes commandes et résultats de tests ne décrivent pas la version actuelle.
