# Validation FLUX IPTV 0.8.2

Préparation du 24 novembre 2026. Base : archive utilisateur 0.8.1, SHA-256 `8b2b989a73873ff371be62de938f97f9723b96ec225882d1119c45609dfa10db`.

## Vérifications effectuées

| Vérification | Résultat | Portée |
|---|---|---|
| `swift test --jobs 4`, Swift 6.2 Linux | 98 tests, 0 échec | Cœur Foundation ; logique et régressions |
| Garde SwiftSyntax | 68 fichiers, 0 déclaration attribuée invalide | Sources et tests |
| Analyse syntaxique des 45 fichiers partagés | Succès pour macOS 14, iOS 17 et tvOS 17 | Analyse seule, sans SDK Apple ni résolution des types des frameworks |
| Générateur Xcode | 3 cibles, 45 fichiers partagés | Ressource RoomBakes reliée aux trois phases de ressources |
| Scripts shell et fichiers plist | Syntaxe/format valides | Installateur non exécuté sur Mac |

Les tests couvrent notamment les indices du carrousel et les bornes du catalogue, les commandes Haut/Bas/Retour, la profondeur du coffret, les thèmes et leur migration, l’assignation atomique des favoris, le routage des bandes-annonces, les homonymes, titres numériques et identifiants de sources externes. Le journal complet est fourni dans `validation/core-tests.txt`.

## Essais réels des descriptions publiques

Le transport et le service ont été compilés et exécutés sous Swift 6.2 Linux, avec des requêtes publiques par titre/année. Aucun compte IPTV n’a servi à ces essais ; les traces ne contiennent aucun synopsis complet.

| Appel final | Résultat observé |
|---|---|
| Interstellar (2014), Wikipédia | Fiche correcte, 783 caractères |
| Interstellar (2014), Allociné | Fiche 114782, 244 caractères |
| Breaking Bad (2008), Wikipédia | Fiche correcte, 2 152 caractères |
| Breaking Bad (2008), Allociné | Erreur réseau `NSURLErrorDomain/-1011` pendant la chaîne de récupération |

La fiche Allociné 3517 de Breaking Bad avait répondu au passage précédent avec 932 caractères. L’erreur du dernier passage ne permet pas de savoir quelle étape Wikipédia → Wikidata → Allociné a refusé la requête. L’accès à toutes les sources ne peut donc pas être garanti. Le modèle affiche un état indisponible et propose le lien de source/recherche ; il ne substitue pas un texte IPTV sous une autre provenance.

Les essais ont confirmé le refus d’une URL HTTP, l’annulation avant et pendant un téléchargement et l’indépendance d’une tâche concurrente non annulée. Le transport partagé a supprimé un plantage reproduit dans la destruction de sessions éphémères du runtime Linux. Les bornes de taille et redirections sont contrôlées pendant le transfert. L’avertissement MediaWiki relatif à `exchars=4000` a été corrigé en utilisant l’introduction et une limite locale.

Traces : `validation/smoke-final-result.jsonl` et `validation/cancellation-result.jsonl`.

## Décors

Le manifeste `FluxIPTVMac/RoomBakes/manifest.json` donne les dimensions, paramètres, tailles et SHA-256 des fonds. `python3 scripts/rooms/verify_rooms.py` contrôle les 18 combinaisons, leurs dimensions 1920 × 1080, leur intégrité et leurs empreintes distinctes. Les fonds ont été inspectés visuellement, avec correction des suspensions qui masquaient l’enseigne du vidéoclub 70. La planche `scripts/rooms/room-previews.jpg` montre les véritables fonds embarqués ; ce ne sont pas des captures de l’application.

La géométrie et les matériaux sont générés par le script fourni ; rendu Cycles et débruitage Open Image Denoise. Aucun modèle, texture ou poster de film importé. L’application utilise ces images précalculées, sans moteur de rendu des pièces en continu. Les budgets des caches et le nombre de boîtes sont des limites du code, pas une mesure de FPS sur appareil.

## Validation Apple bloquée

[La tentative GitHub Actions](https://github.com/M4D135/FluxIPTV/actions/runs/45485025923) sur la branche `work/three-rooms-082` a échoué avant toute étape : aucun runner n’a été affecté aux tâches Linux, macOS, iOS ou tvOS. Aucun journal de compilation n’était disponible. La cause précise de ce refus d’exécution n’a pas été exposée par le connecteur.

Les tests du cœur ont ensuite été exécutés localement comme indiqué plus haut. **Aucun build Xcode complet, lancement de l’installateur Mac, rendu natif, test Siri Remote physique ou essai de lecture IPTV Apple n’est validé dans cette livraison.** L’archive est un candidat source avec installateur, pas un binaire précompilé ni une version qualifiée pour l’App Store.

## Vérification utile sur le Mac / Apple TV

1. Compiler avec le schéma voulu ; ouvrir le catalogue puis chacune des trois sections.
2. Tester Haut, Bas, Retour et les voisins aux limites d’une page ; maintenir une carte pour choisir les favoris et essayer Annuler.
3. Retourner une boîte, observer l’image fixe pendant le délai choisi, ouvrir et refermer la bande-annonce. Vérifier l’arrêt de l’aperçu derrière une feuille et avant la lecture principale.
4. Sélectionner le cadre Description et changer de source. Vérifier un titre connu, un homonyme et un cas indisponible.
5. Ouvrir un coffret, choisir saison/épisode, lancer, puis revenir ; confirmer le retour de focus et les positions de reprise avec la télécommande réelle.
