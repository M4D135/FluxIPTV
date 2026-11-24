# FLUX IPTV 0.8.4 — Pack complet et compilation Apple TV

Version de sources native SwiftUI pour macOS, iOS et tvOS.

**Correctif 0.8.4 :** les indicateurs de progression utilisent leur taille native sur tvOS ; les réglages `controlSize` restent réservés à macOS/iOS. Le job Linux est fixé sur Ubuntu 24.04 pour installer Swift 6.2. GitHub Actions produit les sources complètes, les journaux Xcode et les applications compilées.

**Correctif 0.8.3 :** les trois erreurs Xcode d’accès à `player` depuis le destructeur de l’aperçu sont corrigées. Le nettoyage du lecteur et de son observateur périodique est isolé sur MainActor, sans capturer le contrôleur après sa destruction. Le chargement des groupes audio et sous-titres utilise désormais l’API asynchrone, avec annulation et contrôle de l’item courant.

Le catalogue reste une grille complète. Sélectionner un film ou une série ouvre sa boîte 3D et les quatre voisins au maximum.

## Trois espaces, six thèmes chacun

| Contenu | Espace | Présentation |
|---|---|---|
| Films | Cinéma | Hall, salle, fauteuils, éclairage de séance |
| Séries | Vidéoclub | Rayonnages, comptoir, coffrets |
| Direct | Salon TV | Canapé, meuble TV, lumières domestiques |

Les six thèmes restent disponibles : Néo 80–90, Cinéma de minuit, Salon 70, Palace Art déco, Scandinave et Futur néon. Dans **Réglages → Interface**, chacun des trois espaces possède son propre choix. Les anciennes préférences du vidéoclub sont migrées vers Films et Séries sans écraser un réglage déjà choisi.

Les 18 fonds HD sont fabriqués par un script Blender à partir de géométrie et de matériaux procéduraux originaux, puis précalculés en JPEG 1920 × 1080. Le rendu utilise Cycles et le débruitage Intel Open Image Denoise. Il ne s’agit pas du runtime GPU FERRO. Aucun calcul de pièce 3D continu n’est exécuté dans l’application. Les boîtes interactives utilisent SceneKit/Metal.

Le script reproductible, le manifeste et la planche des décors sont dans `scripts/rooms/`. Les images de cette planche sont les fonds embarqués, pas des captures d’écran de l’application.

## Piloter une boîte

| Contexte | Commande | Résultat |
|---|---|---|
| Grille | Clic / OK | Prendre la boîte |
| Grille | Appui long | Choisir les listes de favoris |
| Boîte sélectionnée | Haut, OK ou Lecture/Pause | Regarder/reprendre le film ; ouvrir le coffret d’une série |
| Boîte sélectionnée | Gauche / Droite | Boîte précédente / suivante |
| Boîte sélectionnée | Bas | Sélectionner la barre d’actions, sur Favoris |
| Boîte sélectionnée | Menu / Retour | Reposer et retrouver la grille |
| Barre d’actions | Gauche / Droite, puis OK | Choisir puis activer un bouton |
| Barre d’actions | Haut / Retour | Revenir à la boîte |
| Description sélectionnée | Gauche / Droite ou Précédent / Suivant | Passer à IPTV, Allociné ou Wikipédia |
| Description sélectionnée | OK | Ouvrir la source disponible |
| Miniature de bande-annonce | Clic ou action Bande-annonce | Ouvrir la bande-annonce en plein écran |
| Bande-annonce plein écran | Retour | Retrouver la boîte |
| Film plein écran | Retour | Arrêter la lecture et retrouver la boîte |
| Coffret ouvert | Gauche / Droite | Saison précédente / suivante |
| Coffret ouvert | Haut / Bas | Parcourir les épisodes, puis les pages |
| Coffret ouvert | Retour | Fermer le coffret |

Sur Mac, le glissement de la souris et le trackpad à deux doigts font tourner la boîte. **Manipuler** donne aussi accès à la rotation par directions. Sur Apple TV, la rotation continue est réservée à ce mode ; les swipes ordinaires servent à la navigation. Les boutons TV/Home, Siri et le volume matériel restent gérés par le système.

Sur Mac : **⌘F** ouvre la recherche ; **⌘⇧F** bascule le plein écran natif. Réduction des animations et contrastes système restent pris en compte.

## Verso : image, puis bande-annonce

Le cadre supérieur tente d’extraire une véritable image du film. Si le format ou le serveur le refuse, une image de la bande-annonce native ou le panorama fourni par l’IPTV peut servir de secours. La provenance de l’image reste indiquée ; une jaquette n’est pas présentée comme une image extraite du film.

**Réglages → Interface → Aperçu au dos de la boîte** : démarrage automatique activable et délai **3, 5 ou 10 secondes** (5 secondes par défaut). Le délai commence après la préparation de l’image fixe. La vidéo démarre en sourdine et reste dans son cadre, avec un fondu de 0,5 seconde au démarrage effectif. Elle ne déplace pas la sélection et ne se lance pas en boucle. Sans image disponible, la bande-annonce reste accessible par une action explicite.

Un clic sur la miniature ouvre le lecteur plein écran. Les URL vidéo directes MP4, M4V, MOV et HLS sont prises en charge nativement selon leurs codecs. Les pages YouTube, Vimeo et Dailymotion restent des liens externes explicites (QR sur tvOS) ; l’application n’extrait pas leur flux vidéo.

Extraction, temporisation et lecteur d’aperçu s’arrêtent en quittant le verso, en changeant de titre ou en passant en arrière-plan. Le passage à une vidéo plein écran attend l’annulation de l’extraction. Une seule vidéo d’aperçu est active. Lors de la lecture principale, le décor et la scène des boîtes sont retirés.

## Description : une source à la fois

Le cadre du synopsis affiche clairement **IPTV / Allociné / Wikipédia**. Sélectionner Description ou cliquer dans son cadre, puis utiliser précédent/suivant, change le texte et sa provenance.

- **IPTV** utilise la description du fournisseur. Aucun texte extérieur ne la remplace sous ce nom.
- **Wikipédia** utilise l’introduction française d’une fiche dont le titre et le type de média correspondent. Quand l’année est fournie, la correspondance est vérifiée via Wikidata. Le lien de source donne accès aux auteurs et à l’historique, avec mention CC BY-SA.
- **Allociné** utilise l’identifiant de film ou série lié dans Wikidata, puis le synopsis structuré public de cette fiche. Les redirections et les identifiants sont vérifiés. Aucun identifiant de fiche n’est deviné.

Les homonymes non résolus, sources absentes, réponses bloquées ou pages sans synopsis structuré affichent un état indisponible et un lien de recherche ou de fiche. Les sources externes sont chargées uniquement lorsqu’elles sont choisies. Les requêtes utilisent le titre public et l’année, jamais l’adresse du flux IPTV ni ses identifiants. Le cache des descriptions reste en mémoire, limité à 24 entrées. Chaque téléchargement est borné à 2 Mio et 18 secondes.

## Favoris et coffrets

L’appui long sur une carte, l’étoile et l’action Favoris ouvrent la même feuille : cocher les listes, créer éventuellement une liste, puis **Enregistrer**. **Annuler** ne modifie rien. Un message confirme l’enregistrement. Les listes Films, Séries et Direct restent séparées.

Le coffret d’une série est plus épais et sa couverture s’ouvre physiquement pour présenter les saisons et épisodes. Les miniatures proviennent du fournisseur ; les positions de reprise existantes sont conservées. Le filtre « À reprendre » du catalogue concerne les films ; il ne prétend pas agréger automatiquement l’historique des épisodes dans un coffret.

## Installer

L’archive contient les sources et l’installateur Mac, pas un binaire Apple précompilé.

1. Sur Mac, quitter l’ancienne app et arrêter le lancement depuis Xcode.
2. Décompresser, puis ouvrir **Installer Flux IPTV.command**. L’installateur compile sur ce Mac et vérifie le démarrage ; cette vérification ne remplace pas un essai de lecture.
3. Vérifier **0.8.4** dans la barre FLUX. Les réglages se trouvent dans Interface.

Prérequis de déploiement : macOS 14, iOS 17 ou tvOS 17. Installer Xcode complet pour compiler ; les API de verre natif utilisent le SDK/OS 26 lorsqu’ils sont disponibles. Sur iPhone/iPad ou Apple TV, ouvrir `FluxIPTV.xcodeproj`, choisir **FluxIPTViOS** ou **FluxIPTVTV**, puis renseigner l’équipe de signature pour un appareil physique.

Le Mac garde AVPlayer natif ; le bouton VLC externe reste disponible pour les formats incompatibles. Les cibles iOS/tvOS conservent l’intégration VLC expérimentale de la base. Les identifiants d’application et les préférences existantes sont conservés. Lire `LISEZ-MOI INSTALLATION.txt` pour les détails de signature et de Trousseau.

## Validation

Le statut précis des vérifications de cette livraison est dans [docs/VALIDATION-0.8.4.md](docs/VALIDATION-0.8.4.md). Les tests unitaires du cœur ne démontrent ni la compilation des frameworks Apple, ni la fluidité réelle, ni la lecture des flux du fournisseur. Aucun EPG n’a été ajouté dans cette version.

## GitHub Actions et pack complet

Le dépôt complet est [M4D135/FluxIPTV](https://github.com/M4D135/FluxIPTV). Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) se lance à chaque push sur `main`, sur les branches de travail des trois univers, lors des pull requests ou à la demande.

Actions exécute les tests du cœur, vérifie les 18 décors et le projet généré, puis compile séparément macOS, iOS Simulator et tvOS Simulator. Les journaux et les résultats Xcode sont conservés même lorsqu’une compilation échoue. Une compilation réussie fournit une archive de l’application correspondante ; les builds iOS/tvOS sont destinés aux simulateurs et le build Mac n’est ni signé pour distribution ni notarié.

Un job indépendant prépare le **pack complet des sources du commit exécuté**, avec empreinte SHA-256 et identifiant du commit. Il inclut le projet Xcode, l’installateur, les tests, la documentation et tous les décors. La présence de ce pack ne vaut pas validation des compilations : consulter les résultats de chaque job dans la même exécution. Voir [docs/CI.md](docs/CI.md) pour les téléchargements et la relance.

### Vérifications locales

```bash
swift test
bash scripts/check-state-declarations.sh
python3 scripts/rooms/verify_rooms.py
bash scripts/build-platforms.sh macOS
bash scripts/build-platforms.sh iOS
bash scripts/build-platforms.sh tvOS
```

Les versions précédentes sont conservées dans [docs/HISTORIQUE.md](docs/HISTORIQUE.md). Leurs anciennes commandes et résultats de tests ne décrivent pas la version actuelle.
