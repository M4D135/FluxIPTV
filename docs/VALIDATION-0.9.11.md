# Validation de FLUX IPTV 0.9.11 — build 52

La 0.9.11 fait du thème du dock le thème de l’application. Les fenêtres le prennent aussi : la colonne, les panneaux de la télévision, le panneau d’un titre, les fiches, les réglages, la feuille d’une source, les messages, le plan des zones et la légende d’une zone. Néon entoure ainsi chaque fenêtre de son tube de lumière, Art déco de son cuivre, Biseaux de son relief gris. Un réglage dit ce que le thème habille : le dock et les fenêtres, le dock seulement, ou les fenêtres seulement.

Elle corrige aussi deux défauts vus sur l’Apple TV HD de la chambre : le préréglage Fluide, qu’Automatique choisit pour ce modèle, coupait les fonds, et la page des Réglages descendait sous sa fenêtre.

David l’a demandé le 28 novembre 2026 :
- « theme dock super mais ça serai bien aussi que l'egfet neon soit sur toutes les fenetres aussi, en gros fait theme general pas que dock, ou au choix donc theme general et on choisit que doc ou le reste » ;
- « un systeme de theme bien elaboré » ;
- « bug dans options ça deborde, et sur appletv gen 3 chambre, j'ai aucun ecran de fond », avec une photo de son téléviseur : la page Interface des Réglages, ses sections dessinées sous la fenêtre jusqu’au pied de l’écran, sur un fond noir.

Pour le reste, les validations de la 0.9.10 ([VALIDATION-0.9.10.md](VALIDATION-0.9.10.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 28 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- au simulateur Apple TV 4K (4e génération), en 1080p, sous tvOS 27.2 ;
- sur l’état final des sources.

## Ce qui change pour la vérification

- **Le thème des fenêtres.** Seize des dix-huit thèmes habillent aussi les fenêtres, chacun à sa manière :
  - sur le verre de l’application, Couleurs l’entoure des deux couleurs de l’écran, Tactile l’éclaircit et arrondit ses coins, Givre le dépolit et resserre ses coins, Verre nocturne le teinte de bleu nuit sous un reflet ;
  - à la place du verre, Fumé, Néon, Galets, Gélule, Collines, Biseaux, Huit couleurs, Quatre couleurs, Bureau vert, Phosphore, Néon 90 et Art déco posent une plaque sombre dans le cadre de leur thème. Le néon est fait de trois traits superposés, larges et pâles à fins et vifs, et d’un cœur blanc, aux couleurs de l’écran ; Néon 90 a les siennes, magenta et cyan.

  Verre et Sans fond laissent les fenêtres en verre, comme avant. L’intérieur d’une plaque reste sombre, pour le blanc de ce qui y est écrit.
- **Ce qui garde le verre.** Les champs de recherche, les boutons de la barre du haut, la barre de l’accueil et les commandes posées sur l’image pendant la lecture gardent le verre de l’application, quel que soit le thème.
- **Ce que le thème habille.** Réglages › Thème et dock (la page s’appelait Dock) › Thème : « Le thème habille » propose le dock et les fenêtres (au départ), le dock seulement, ou les fenêtres seulement. Le dock seulement rend aux fenêtres le verre de la 0.9.10 ; les fenêtres seulement rendent au dock le thème Verre. Un écran qui garde son propre thème l’applique à ses fenêtres comme à son dock ; le menu du dock, sur le Mac, change toujours le thème choisi, même quand le dock ne le montre pas.
- **Le studio.** Son étagère Dock s’appelle Thème : elle essaie le thème sur un dock et, à côté, sur une fenêtre, chacun selon ce que le thème habille.
- **Le dessin.** Une plaque est faite de remplissages et de traits, sans ombre, sans flou ni canevas de la taille de la fenêtre ; elle est posée derrière sa fenêtre, qui garde sa taille, et la télécommande ses places. Les thèmes posés à la place du verre ne prélèvent rien derrière leurs fenêtres.
- **Fluide garde les fonds.** Depuis la 0.9.4, Automatique choisit Fluide pour une Apple TV HD, et Fluide coupait le verre, les mouvements, l’aperçu des chaînes et les fonds. Il garde désormais les fonds : une image fixe, décodée d’avance une fois à la taille de l’écran (1920 × 1080 sur une Apple TV depuis la 0.9.10), sans mouvement. Le préréglage appliqué par Automatique est noté sous une nouvelle clé (`fluxiptv.quality.applied.v2`) : une Apple TV HD restée en Automatique reçoit une fois Fluide tel qu’il est maintenant, et retrouve ses fonds. Les réglages choisis à la main ne changent pas ; des fonds coupés à la main font afficher « Personnalisé ».
- **Les Réglages dans leur fenêtre.** La page des Réglages est coupée au bord de sa fenêtre, en haut et en bas ; sur les côtés, la marge garde entière une touche qui grandit sous la télécommande.

## Exécuté

| Vérification | Résultat |
|---|---|
| Vérification de types : Mac (production, et avec le banc du Mac), tvOS, tvOS du banc, parcours de la télécommande, variante App Store pour tvOS, et iPhone et iPad (simulateur) | Aucune erreur. |
| Tests du cœur (`swift test`) | 222 tests, aucun échec. |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 95 captures et 29 scénarios de touches, en 5 min 48 ; celui qui choisit Fluide au clavier trouve les fonds gardés. Comme en 0.9.10, ce mode laisse de côté les scénarios de la recherche qui demandent la fenêtre active. |
| Les dix-huit thèmes du Mac, chacun capturé sur l’écran de la télévision avec sa colonne, ses panneaux et son dock, regardés en planche | Chacun habille la colonne, la liste des chaînes et le panneau de la chaîne à la manière de son dock ; Verre et Sans fond les laissent en verre. Le texte reste net partout, sous les quatre thèmes sur verre comme sur les plaques, et le liseré de Couleurs paraît. Néon 90, Verre nocturne et Art déco montrent leurs docks dessinés. |
| Banc Apple TV complet (`scripts/test-tvos-catalog-ui.sh`), Apple TV 4K (4e génération) en 1080p sous tvOS 27.2 | 36 écrans capturés — les 33 de la 0.9.10, les Réglages en Fluide et deux écrans dans un thème —, le focus natif sur le contrôle attendu dans chacun, et les 32 parcours de la télécommande : aucun échec, en 24 min 57, dont 19 min 56 pour les parcours. Les six parcours de mesure, qui ne tournent qu’à la demande, y sont sautés. |

## Ce que la vérification a trouvé

- **Le verre posé derrière une fenêtre la floutait.** Dans un groupe de verre, celui que dessine le système pour réunir les panneaux voisins, un verre posé seul derrière une fenêtre est dessiné au-dessus de ce qu’elle tient : les quatre thèmes sur verre de la première version rendaient la colonne et les panneaux flous. Ils posent désormais le verre sur la fenêtre elle-même, comme sans thème.
- **Le liseré de Couleurs passait sous le verre.** Tracé par-dessus la fenêtre après son verre, il n’apparaissait pas sur la planche : le verre le recouvrait. Il appartient désormais à la fenêtre, comme la teinte, et se dessine au-dessus de son verre.
- **Sur l’Apple TV HD, la page des Réglages débordait de sa fenêtre.** La photo de David montre, en Fluide, la section « Présentation et commandes » dessinée sous la fenêtre, jusqu’au pied de l’écran. Au simulateur, sous tvOS 27.2, la même page s’arrête au bord de sa fenêtre, avec ou sans verre : la défaillance tient à l’Apple TV, sous tvOS 26.6.1. La page est désormais coupée par l’application elle-même, en haut et en bas, comme la liste des chaînes l’était déjà.
- **Fluide coupait les fonds.** C’est ce que disait sa tuile, « Ni verre, ni mouvement, ni fond, ni aperçu » : l’Apple TV HD de la chambre montrait donc les écrans sur la couleur unie de chacun. Ce que coûte un fond fixe n’a pas été mesuré sur l’Apple TV HD (voir [Non vérifié](#non-vérifié)).
- **La CI de la 0.9.10 (`6c27b8b`)** : les tests du cœur ne compilaient pas sous Linux. Deux classes de tests mêlaient des tests isolés sur le fil principal et d’autres qui ne l’étaient pas, et Swift 6.2 sous Linux n’en construit pas la liste. Ces tests s’exécutent désormais sur le fil principal sans changer d’isolement (`40eaf2f`). Le reste est passé sur la branche et sur main, à deux défaillances des machines hébergées près :
  - sur la branche, le travail macOS a perdu son exécuteur (« The hosted runner lost communication with the server ») ; le même commit est passé sur main ;
  - sur main, l’Apple TV au simulateur, sous tvOS 26.5, a passé ses 33 écrans et tous ses parcours, comme sur la branche, mais l’export des pièces jointes des parcours, borné à trente secondes, n’a pas répondu à temps. Cette machine avait mis 67 minutes pour les parcours, sur les 70 accordées, et le travail 100 sur 110 : les bornes sont relevées (voir [CI.md](CI.md)).
- **Le banc Mac n’emportait pas les docks dessinés.** Il copiait dans son application les fonds des écrans, mais pas les images des docks de Néon 90, Verre nocturne et Art déco : depuis leur arrivée, en 0.9.4, ses captures de ces thèmes montraient les icônes simples sur lesquelles le dock se replie. Il les copie désormais. L’application les a toujours emportées, et le banc Apple TV, qui construit l’application elle-même, les avait.
- **Une capture vide, une fois.** Le premier banc Mac de la 0.9.11 a rendu une capture de l’accueil vide (« Native header capture is empty or uniform ») ; refaite, puis dans le banc complet, elle est bonne.

## Ce que les bancs vérifient de nouveau

- **Le thème sur l’Apple TV.** Le banc Apple TV capture de nouveau deux écrans dans un thème : la télévision en Néon et les films en Art déco, avec le focus natif sur le contrôle attendu, comme les autres écrans.
- **Les Réglages en Fluide.** Une capture montre la page Graphismes comme une Apple TV HD la montre, sans verre ni mouvement (`settings-graphics-light`). Sur la CI, sous tvOS 26.5, elle montre la page sous la version de tvOS des Apple TV de David.
- **Le thème sur le Mac.** Les captures des thèmes de la galerie montrent désormais la colonne et les panneaux de l’écran dans le thème, en plus du dock ; les docks dessinés y paraissent tels qu’ils s’affichent.
- **Fluide sur le Mac.** Le scénario du banc Mac qui choisit Fluide au clavier exige désormais que les fonds restent.
- **Les tests du cœur :** ce que chaque portée habille, les thèmes qui laissent le verre aux fenêtres ; Fluide garde les fonds, et des fonds coupés ne sont plus aucun préréglage.
- **`FLUX_TVOS_CAPTURES`** joue seulement les captures nommées du banc Apple TV, sans les parcours : un dessin se regarde de nouveau en quelques minutes.

## Non vérifié

- **Sur une Apple TV.** Rien n’a été installé sur une Apple TV : ni les thèmes, ni les fonds de Fluide, ni la page des Réglages coupée n’y ont été vus. La page coupée n’a été vue qu’au simulateur, sous tvOS 27.2, où elle ne débordait pas ; sur l’Apple TV HD, il faut la regarder de nouveau.
- **Ce que coûtent les fonds sur une Apple TV HD.** Une image fixe est décodée d’avance et ne bouge pas, et le diaporama passe d’une image à l’autre en fondu toutes les 15 secondes au plus souvent. Ce que cela coûte sur l’Apple TV HD, comme les traits et les plaques des thèmes, n’est pas mesuré.
- **Les autres listes sur tvOS 26.** La colonne et les autres listes ne sont pas coupées par l’application ; au simulateur, elles s’arrêtent au bord de leur fenêtre. Si l’une d’elles déborde aussi sur l’Apple TV HD, le même remède s’y appliquera.
- **Chaque fenêtre dans chaque thème.** Les planches montrent les dix-huit thèmes sur l’écran de la télévision du Mac, et deux thèmes sur l’Apple TV. Les fiches, les réglages, la feuille d’une source et les messages n’ont été capturés que dans le thème du banc.
- **iPhone et iPad** : les fenêtres y prennent le thème comme ailleurs. La vérification de types passe ; seule la CI les compile entièrement.
- **La CI de GitHub** : celle de la 0.9.11 part avec son envoi, et son résultat n’est pas dans cette page.

## Limites connues

- **Les couleurs des écrans** (Réglages › Interface) donnent toujours aux thèmes leurs deux couleurs, et le fond uni quand un écran n’a pas d’image. Leurs noms et leurs descriptions parlent encore des décors de la 0.8 ; les ranger dans le thème est pour une prochaine version.
