# Validation de FLUX IPTV 0.8.9 — build 29

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

## Vérifications

Les tests du cœur couvrent la détection, les faux positifs, les filtres composés et le stockage par contexte. Les sept scénarios tvOS du build 28 restent présents avec les mêmes exigences de taille, de position, de correspondance du focus et de visibilité.

Quatre scénarios natifs supplémentaires utilisent un même catalogue mixte de neuf chaînes : trois françaises, deux espagnoles, deux britanniques et deux sans pays identifié. Ils capturent France, Espagne, le sélecteur de pays et la restauration de la navigation, puis vérifient les identifiants réellement retournés par le filtre de production. Le dernier ouvre ContentView sans sélection injectée et exige le retour du focus natif sur la chaîne mémorisée après lecture des préférences par une nouvelle bibliothèque.

Le scénario du sélecteur vérifie aussi le modèle IPTVLibrary réel avec une suite UserDefaults isolée : pays/catégorie/recherches/sélection, aller-retour entre TV et Films, écriture des préférences, nouvelle instance de la bibliothèque et rafraîchissement du catalogue. Ce contrôle ne prétend pas simuler un redémarrage physique de l’Apple TV ou des déplacements à la Siri Remote.

Le résultat applicable est celui du workflow attaché au commit exact livré. Une compilation Apple TV appareil vérifie le SDK et le binaire Release, sans mesurer la fluidité d’un appareil physique. Les captures de démonstration ne prouvent pas la lecture d’une chaîne ou d’une bande-annonce distante.
