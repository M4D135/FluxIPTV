# Validation de FLUX IPTV 0.8.8

## Périmètre de la refonte

- Fiche plein écran SwiftUI, synopsis IPTV et un seul aperçu ; ancienne présentation SceneKit et cartes voisines retirées du chemin utilisateur.
- Grille réellement démontée tant que la fiche est visible ; aucune mise à l’échelle de toute la scène.
- Apple TV : grandes entrées TV/Films/Séries/Recherche, catégories horizontales, vignettes 16:9 avec un aperçu actif, décors existants conservés.
- Premier démarrage sans source : accueil Charger une liste. Le chargement des sources enregistrées est synchrone et ne provoque pas d’invitation intempestive.
- Surfaces tvOS sans flou, images de décors plafonnées, animations de focus/transition conservées. Le lancement normal Apple TV utilise Release ; le build ARM64 CI vérifie cette configuration.
- Résolveur local de bandes-annonces publiques YouTube et lecture AVPlayer tvOS ; aucun renvoi QR/iPhone.
- Correction de disponibilité des API du Trousseau sans migration des identifiants.

## Corrections de finalisation

- Correction de la déclaration conditionnelle du focus qui bloquait les quatre compilations Apple de la première révision 0.8.8.
- Build 23 : découpage de l'expression principale SwiftUI en sous-vues opaques pour supprimer le second blocage de compilation (« unable to type-check this expression in reasonable time »), sans effacement de type ni changement des animations.
- Arrêt immédiat de l'aperçu lors d'un changement de chaîne, lecteur et état rattachés à l'identifiant de la chaîne courante ; les erreurs d'URL conservent cette identité et les tâches annulées ne remplacent pas l'aperçu actif.
- Retour depuis la bande-annonce traité par le lecteur qui l'a reçu, sans seconde activation de la fiche après fermeture.
- Build 24 : une recherche sans résultat conserve sa demande de focus jusqu'au transfert natif vers l'onglet de contenu courant ; le repli automatique transitoire vers TV ne l'annule plus.
- Les boutons de catalogue déjà dessinés utilisent explicitement le style nu au plus près de leur libellé. Un style `plain` interne reprenait la priorité sur tvOS et ajoutait un large socle blanc derrière la tuile active ; le contour et les animations propres à FLUX sont conservés.
- Build 25 : sept colonnes de jaquettes en densité normale sur Apple TV, afin de garder le titre et les métadonnées dans la zone visible sous les menus. La capture native vérifie désormais aussi la position de la carte focalisée dans la fenêtre et son confinement dans le viewport, pas seulement sa taille relative.
- Build 26 : les saisons et l’épisode de reprise déjà chargés sont installés avant le premier rendu de la fiche. Le bouton « Voir S… · E… » est ainsi disponible dès l’arrivée du focus, qui ne se replie plus sur « Les saisons » pendant une initialisation asynchrone inutile.
- Après fermeture du champ de recherche sur Apple TV, le bouton Retour conserve son gestionnaire tant qu’une recherche filtre encore le catalogue ; il peut donc réafficher tous les titres.
- Les commandes du lecteur principal utilisent aussi le style nu au plus près des boutons, pour ne pas réintroduire le socle blanc derrière leurs cercles de focus.
- Le catalogue Films/Séries tvOS borne chaque carte à la hauteur réelle restant sous les commandes, le champ de recherche et la pagination. Les textes conservent leur taille ; la jaquette utilise l’espace restant, avec ses animations. Cela évite que le titre et les métadonnées de la carte sélectionnée sortent du bas de l’écran 1080p.
- Les contrôles tvOS ne valident plus un focus dont l’identifiant manque par sa seule taille : ils doivent observer le rectangle réel du contrôle attendu et sa correspondance avec le focus natif. Les scénarios incluent désormais une recherche avec résultat et une recherche vide, en plus des cinq écrans précédents. Ils exercent le gestionnaire de validation et le filtre réels, sans prétendre reproduire une saisie à la télécommande physique.
- La garde SwiftParser rejette maintenant les erreurs de syntaxe, y compris dans les branches de compilation conditionnelle, en plus des déclarations SwiftUI invalides.
- Conservation de la sourdine demandée pendant le chargement asynchrone d’une bande-annonce ; retour à la fiche et commande de son partagent le même état que le lecteur.
- Nouvelle tentative après une erreur de session YouTube depuis le bouton Lire, en conservant la préférence de son.
- Validation de la recherche après la fin du filtrage, pour éviter de focaliser ou d’ouvrir un ancien résultat.
- Rétablissement conjoint de la sélection et du focus natif après une recherche vide, même si le système sélectionne brièvement une autre rubrique.
- Suppression du fond blanc de focus natif sur les commandes personnalisées : un seul style de bouton, contour fin et animation de la vignette conservés.

## Qualification du build 27

- Réunion des corrections de focus de la branche principale et des cartes tvOS adaptées au viewport, avec conservation des observations logiques et natives après recherche.
- Les couleurs de sélection restent au-dessus de la surface sombre ; le mode compact tient compte du dernier espacement pour conserver sa densité propre.
- Le smoke convertit le rectangle du focus natif par le conteneur déclaré de son parent immédiat, dont la chaîne doit atteindre la fenêtre active. Il le compare ensuite à la sonde du contrôle attendu ; aucune coordonnée attendue ne sert à choisir cet espace.
- Le contrôle du Trousseau iOS/tvOS exige le marqueur de succès et utilise un tableau d’arguments compatible avec le Bash macOS.

## Garde-fous exécutés par la CI

| Vérification | Ce qu’elle établit |
|---|---|
| Tests Swift du cœur | Logique catalogue, sources, navigation, reprise et délais |
| Génération des deux projets | Aucun fichier manquant ou divergence du générateur |
| 18 ressources de décors | Dimensions 3840×2160, empreintes distinctes et intégrité |
| macOS / iOS / tvOS simulateur / tvOS appareil Release | Compilation réelle des SDK Apple |
| Trousseau Mac et SDK iOS/tvOS | Comportement silencieux et disponibilité des API |
| Aperçu TV natif local | Délai, annulation, repli et libération du lecteur |
| Lecteur web YouTube local | Session et contrôles macOS sans dépendance au réseau distant |
| Résolveur natif YouTube | Fixtures de refus/URL, compilation, sonde publique distincte |
| Captures SwiftUI Mac et tvOS | Fiches, sélection épisode, accueil, catégories et bornes du focus natif |

Le résultat applicable est celui du workflow attaché au commit exact de l’archive, pas celui d’une version précédente. Consulter les logs et captures de cette exécution dans GitHub Actions ; une archive de sources seule n’indique pas que toutes les compilations sont réussies.

## Limites explicites

Les fixtures de catalogue ne lisent aucun compte ni flux réel. Les captures sont prises en simulateur/fenêtre native et ne mesurent pas la latence d’une télécommande ou les images par seconde sur le matériel de l’utilisateur. Aucun objectif de 60 images/s n’est déclaré atteint sans mesure sur appareil.

La sonde YouTube peut échouer pour un refus réseau, une connexion exigée ou une vidéo indisponible. Même un AVURLAsset prêt et compatible n’est pas une preuve de lecture complète. Le résolveur refuse les réponses non publiques, les restrictions et les formats protégés ; il ne garantit pas tous les liens YouTube. L’évaluation éventuelle JavaScriptCore est locale, synchrone et hors du fil principal, avec contrôles d’annulation avant/après ; ce n’est pas une préemption CPU dure.

Les préférences de débit/résolution de l’aperçu sont des indications AVPlayer. Elles ne transcodent pas un flux fixe et ne limitent pas la qualité du lecteur principal. Les programmes EPG ne sont pas synthétisés. Le support réel de certains codecs dépend de l’appareil et du moteur de lecture.

La signature Apple de l’utilisateur est nécessaire sur un appareil physique. Le projet n’impose aucune équipe ni aucun certificat.
