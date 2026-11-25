# Validation de FLUX IPTV 0.8.9 — build 37

## Finalisation du build 37 : validation native intégrée

Le build 37 intègre les derniers correctifs du build 36 : les scénarios France/Espagne passent par la restauration de production et le catalogue garde son identité SwiftUI lorsque Retour devient disponible. Le test Pays exige toujours le focus natif et logique sur la première chaîne française dès son démarrage. Il conserve toutes les étapes France → Espagne, réouverture, déplacement vers France et annulation par Menu, puis vérifie le retour à l’onglet TV et la mise en arrière-plan par Menu. Aucun déplacement préparatoire ne masque un échec de restauration.

La revue des captures corrige aussi les libellés au singulier : « 1 élément » et « 1 chaîne ». Les deux projets Xcode portent 0.8.9 / 37. La validation applicable est l’exécution du commit exact livré ; les treize lancements canoniques et les trois parcours de télécommande restent obligatoires.

## Finalisation du build 36 : rangée d’épisodes entière sur Mac

La revue visuelle du build 35 a montré que la barre horizontale native de macOS rognait le bas des cartes d’épisodes. La préférence `.hidden` laisse macOS afficher un indicateur avec une souris ; `.never` empêche cet indicateur de prendre de la hauteur dans cette rangée. Le défilement par les directions, le focus et le trackpad reste disponible. Les dimensions de la boîte, des cartes et les animations sont conservées.

Le build 36 reprend la grande boîte et tous les correctifs de navigation du build 35. Les deux projets Xcode portent 0.8.9 / 36. Les résultats attendus sont ceux du workflow attaché à son commit : les quatre compilations Apple, les 134 tests du cœur, les captures natives et les trois parcours XCUIRemote. La capture Mac de la saison 12 doit montrer le bord inférieur complet des cartes sans barre grise.

Référence du comportement macOS : https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility/hidden

### Initialisation des scénarios de pays et de reconnexion

Une exécution du build 36 a exposé une course dans les scénarios France/Espagne : la fixture affectait une sélection avant la fin du filtrage asynchrone, puis le focus natif choisissait Pays pendant que les cartes étaient encore absentes. Ces scénarios enregistrent maintenant le pays et la chaîne dans des préférences isolées, recréent la bibliothèque et passent par la restauration de production, comme le scénario de chaîne mémorisée. La sélection n’est pas injectée dans la vue. Les exigences de focus sur la chaîne, de visibilité, de géométrie et de contenu filtré restent identiques.

Le scénario de source indisponible commence sur Pays, contrôle choisi par le moteur natif et confirmé dans l’arbre d’accessibilité. Il conserve les trois déplacements Bas / Haut / Bas entre Pays et Reconnecter, la comparaison entre focus natif et surbrillance et les trois captures correspondantes. Ces ajustements concernent le harnais de validation ; les commandes de l’application sont conservées.

L’exécution initiale [45663229094](https://github.com/M4D135/FluxIPTV/actions/runs/45663229094) a produit onze PNG canoniques, mais seulement neuf rapports `ready` : France et Espagne avaient le statut `failed`. Un des trois tests XCUIRemote avait réussi. La présence d’une image ne vaut donc pas validation de son focus ; la livraison exige les rapports et tests réussis du commit final.

### Identité du catalogue lors de l’activation de Retour

L’exécution [45668822249](https://github.com/M4D135/FluxIPTV/actions/runs/45668822249) a ensuite réussi les trois parcours XCUIRemote, mais les captures France/Espagne restaient sur Pays au lieu de leur chaîne mémorisée. Les préférences étaient correctement restaurées ; le scénario avec recherche visible réussissait aussi ses trois lancements à froid.

Le modificateur `fluxExit` changeait de branche SwiftUI lorsque le focus quittait l’onglet TV, puisque cette transition activait la commande Retour. Cette structure conditionnelle pouvait recréer les contrôles pendant leur remise de focus. Le modificateur reste désormais présent ; seule son action devient `nil` quand le système doit gérer Menu. Les exigences des captures restent identiques. Le parcours pays vérifie également Menu vers l’onglet TV, puis Menu vers l’accueil système, sans assimiler une application arrêtée à une sortie normale.

Référence de l’action optionnelle : https://developer.apple.com/documentation/swiftui/view/onexitcommand(perform:)

## Finalisation du build 35 : navigation réelle

- La grande boîte, la description et les commandes de lecture du build 34 sont conservées, avec l’absence de lecteur de bande-annonce dans la fiche.
- Un échec de chargement libère la restauration en attente ; les contrôles de reconnexion suivent le focus natif et leur surbrillance reste synchronisée.
- Les choix natifs provisoires pendant le chargement ne remplacent pas la page ni la chaîne mémorisées. Retour annule la demande en attente et empêche la réouverture involontaire de la recherche.
- Les trois parcours XCUIRemote utilisent les directions, Valider et Menu dans le simulateur : France → Espagne puis fermeture sans changement, sortie et retour sur la chaîne restaurée, navigation sur la reconnexion après échec de source. Le test compare `hasFocus` au marqueur non interactif de la sélection dessinée.
- Onze captures d’actions sont attachées au résultat Xcode et exportées, en plus des onze captures canoniques et des trois lancements à froid de restauration. Aucun target de test n’est ajouté aux projets livrés.
- Les huit configurations des deux projets affichent 0.8.9 / 35. Le résultat applicable reste celui du workflow attaché au commit exact livré.

## Fiches conservées depuis le build 34 : description et grande boîte

Ce build réunit la nouvelle fiche, la correction de l’API pays et la restauration du focus arrivée en parallèle sur la branche principale. Les sondes AppKit des fiches contrôlent directement la boîte et le bouton Lecture ; elles ne dépendent pas de l’exposition de l’arbre d’accessibilité par le runner.

- La fiche d’un film ou d’une série présente une unique grande boîte du titre sélectionné avec sa jaquette, à côté de la description. Le format suit la règle du catalogue : VHS avant 2000, DVD dès 2000 et DVD si l’année manque.
- Aucun lecteur ni aperçu de bande-annonce n’est créé par la fiche. Elle ne charge aucune bande-annonce et ne propose plus de commande de bande-annonce ou de plein écran vidéo d’aperçu.
- Les actions Lecture, Description complète, Favoris et Retour restent disponibles, ainsi que le choix de l’épisode pour une série. La lecture principale démarre par la commande dédiée.
- Les réglages de lecture automatique et de délai des bandes-annonces sont retirés. Les réglages et le comportement des aperçus des chaînes TV restent disponibles.
- Le catalogue, les filtres par pays, la mémoire de navigation et les marges du rayon de saisons du build 32 sont conservés.

La validation de cette présentation repose sur l’exécution attachée au commit exact livré : compilations Apple, captures des fiches Film/Série et contrôles natifs du focus, de la boîte visible et de l’absence de lecteur de bande-annonce. Le résultat applicable est celui de cette exécution.

- La détection des pays utilise désormais `Locale.Region.isoRegions`, disponible sur toutes les versions minimales du projet, à la place de l’API dépréciée `Locale.isoRegionCodes`. Les groupements à plusieurs pays (EU, EZ) sont écartés avant de conserver les codes de deux lettres. Les faux positifs EU/EZ sont couverts dans la suite existante.

## Historique : finalisation des builds 30 à 33

- Réunion de la branche pays/mémoire et de la branche principale, sans abandonner les corrections de focus de recherche, la grille dans la zone sûre ou les contrôles natifs stricts.
- La sélection logique est publiée dès la fin du filtrage, puis réaffirmée avec le focus natif après le montage des résultats. Une transition du moteur de focus vers l’en-tête ne peut plus annuler ce transfert.
- Le test de recherche Mac observe ensemble sélection logique et focus natif, avec quatre observations stables. Les onze scénarios tvOS conservent leurs exigences géométriques et de visibilité.
- Les couleurs de sélection restent au-dessus du fond sombre. Le calcul des colonnes conserve l’espacement final prévu.
- Les builds 29 et 30 ont révélé que la présentation native du sélecteur pouvait ignorer l’affectation dans `onAppear` comme la préférence de focus, puis sélectionner « Tous les pays ». Le build 31 attend la première entrée de focus réellement signalée par le binding de la feuille et le transfère une seule fois vers le pays mémorisé. La demande est consommée avant l’écriture pour laisser ensuite la navigation libre. Aucun délai arbitraire ni boucle de recentrage n’est utilisé ; un pays disparu se replie sur « Tous les pays ». Le contrôle géométrique de `country-picker` reste inchangé.
- Le build 32 porte la marge supérieure du rayon des saisons de 14 à 32 points : la première carte sélectionnée conserve son contour et ses arrondis pendant le zoom et le déplacement vertical. Les animations et les exigences des contrôles natifs sont conservées.
- Le second passage du build 32 sur `main` a révélé une course à la restauration : les filtres et la chaîne mémorisée étaient exacts, mais le champ de recherche conservait parfois le focus UIKit. Le build 33 attend que la cible soit montée et que le navigateur ait reçu sa première entrée de focus natif avant un transfert unique. Il libère explicitement les champs de recherche, protège la sélection contre le repli temporaire du moteur natif et annule la demande lors d’une action explicite de recherche ou de sélection. Le contrôle `live-restored` est répété sur trois lancements à froid, sans assouplissement des assertions.
- Les projets du build 33 affichaient 0.8.9 / 33 ; le centre de contrôle lit la version et le build du bundle pour éviter les anciens numéros figés dans l’interface.

## Pays des chaînes TV

- Détection au début des catégories, avec limite de mot : `FR |`, `[FR]`, `ES -`, noms de pays français/anglais et drapeaux.
- `UK` est rattaché à `GB`, `USA` à `US`. Les préfixes techniques nus `TV` et `SD` ne sont pas interprétés comme des pays.
- Les catégories originales restent intactes. Les catégories non identifiées sont conservées sous « Pays non identifié ».
- L’index calcule les pays une fois par catégorie distincte ; le déplacement du focus ne refait pas cette analyse.
- Pays, recherche et favoris se combinent. Les Films/Séries ne reçoivent aucun filtre pays.
- Le menu pays et ses effectifs utilisent le catalogue TV complet, même après une recherche vide.

## Mémoire de navigation

- Préférences versionnées, séparées par source et par section TV/Films/Séries.
- Dernière source/section, pays, catégorie, recherche, recherche de catégories, liste de favoris, filtre des films à reprendre, page et dernière carte sélectionnée.
- Écriture différée pendant la navigation, puis sauvegarde explicite au changement de contexte et quand l’application quitte le premier plan.
- Aucun effacement pendant un chargement temporairement vide. Les références périmées sont vérifiées sur un catalogue complètement chargé.
- Retour vers le catalogue et changement de section conservent les filtres ; la réinitialisation passe par une commande explicite.
- Restaurer une sélection ne démarre aucune lecture.

## Périmètre des vérifications

Les tests du cœur couvrent la détection, les faux positifs, les filtres composés et le stockage par contexte. Les sept scénarios tvOS du build 28 restent présents avec les mêmes exigences de taille, de position, de correspondance du focus et de visibilité.

Quatre scénarios natifs supplémentaires utilisent un même catalogue mixte de neuf chaînes : trois françaises, deux espagnoles, deux britanniques et deux sans pays identifié. Ils capturent France, Espagne, le sélecteur de pays et la restauration de la navigation, puis vérifient les identifiants réellement retournés par le filtre de production. Le dernier ouvre ContentView sans sélection injectée et exige le retour du focus natif sur la chaîne mémorisée après lecture des préférences par une nouvelle bibliothèque.

Le scénario du sélecteur vérifie aussi le modèle IPTVLibrary réel avec une suite UserDefaults isolée : pays/catégorie/recherches/sélection, aller-retour entre TV et Films, écriture des préférences, nouvelle instance de la bibliothèque et rafraîchissement du catalogue. Ce contrôle ne prétend pas simuler un redémarrage physique de l’Apple TV ou des déplacements à la Siri Remote.

Le résultat applicable est celui du workflow attaché au commit exact livré. Une compilation Apple TV appareil vérifie le SDK et le binaire Release, sans mesurer la fluidité d’un appareil physique. Les captures de démonstration ne prouvent pas la lecture d’une chaîne ou d’un film du fournisseur. Les anciennes vérifications de bandes-annonces des builds 30 à 32 décrivent leur présentation d’alors ; le build 34 ne propose plus de bande-annonce dans les fiches.
