# Validation de FLUX IPTV 0.9.9 — build 50

La 0.9.9 revoit la télécommande de l’Apple TV sur quatre points :
- au bout à droite d’un écran, Droite repart à gauche, à la même hauteur, au lieu de descendre dans le dock ;
- sur une liste, le pointeur devient un pointeur de défilement. Il garde sa hauteur et fait défiler la liste sous lui. Il sort de la liste par ses côtés ;
- le pointeur offre six formes, six couleurs, six tailles, cinq vitesses et trois accélérations ;
- le mode Classique se choisit de nouveau au pointeur, dans les Réglages.

David l’a demandé le 27 novembre au soir :
- « quand on va au bout a droite dans une fentre on va changer au lieu d'allzr dans barre dock , onnreste normal comme lenreste on repart a gauche a mm hauteur, faut un deplacement coherent et logique » ;
- « pour le mode souris super mais ajoute plus de choix de pointeurs, de taille et de vitesse. » ;
- « par contre sur une liste on passe sur un pointeur defilement au survol et on change le fonctionnement au survol de la zone pour haut et bas, on ressort par droite gauche de la zone, sinon c incontrollable » ;
- « trouve une maniere elegante simple facile a piloter lorsquon survole une zone liste en mode souris pour resumer » ;
- « pour basculer de mode c ok standard vers souris mais pas le contraire ».

Il a demandé ensuite : « tu feras tes test en simulateur xcode ». Les parcours ont donc été rejoués au simulateur Apple TV, et non sur les Apple TV du séjour.

Pour le reste, les validations de la 0.9.8 ([VALIDATION-0.9.8.md](VALIDATION-0.9.8.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites les 27 et 28 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- au simulateur Apple TV 4K (4e génération), en 1080p, sous tvOS 27.2 ;
- sur l’état final des sources.

## Les changements

### Au bout à droite, retour à gauche à la même hauteur

- En 0.9.8, sur Apple TV, une flèche Droite donnée après une pause au bord droit d’un écran descendait dans le dock, sur l’icône de l’écran. C’était le cas après Favoris sur une chaîne, au bout d’une ligne des Réglages ou sur le dernier titre d’une grille.
- Désormais, elle revient au contrôle le plus à gauche qui se tient à la même hauteur, comme une ligne de texte reprend à gauche. C’est en général la ligne de la colonne à cette hauteur ; sinon, le premier titre ou la première touche de la ligne.
- « À la même hauteur » veut dire à 24 points près au-dessus ou au-dessous du milieu de ce que l’on quitte. Si rien ne se tient à cette hauteur, la sélection va au contrôle le plus proche en hauteur.
- Sur le banc, Droite après Favoris revient sur « Cinéma », la catégorie de la colonne qui se tient à leur hauteur.
- Ce qui ne change pas :
  - au bout d’une rangée de titres, Droite passe toujours au premier titre de la rangée suivante ;
  - une flèche maintenue s’arrête toujours au bord ;
  - dans le dock, Droite fait toujours le tour de la barre ;
  - un dock placé à droite de l’écran garde Droite ;
  - sur l’accueil, la barre fait le tour comme avant ;
  - Gauche mène toujours à Retour.
- Avec le dock masqué, la bande invisible du bord droit est désormais posée : Droite au bord revient aussi à gauche. En 0.9.8, une flèche vers un bord où rien ne se tenait ne faisait rien.

### Le pointeur de défilement sur les listes

- En mode souris, le pointeur devient un pointeur de défilement au-dessus :
  - de la liste des chaînes ;
  - de la grille des films et des séries ;
  - de la colonne des écrans TV, Films, Séries, Favoris et Recherche ;
  - de la liste des pays.
- Le pointeur de défilement est une capsule debout, avec deux flèches (▲ ▼) et un point.
- Il garde sa hauteur, dans la bande du milieu de la liste. Cette bande s’arrête à un quart de la hauteur de la liste depuis le haut et le bas, et jamais à plus de 160 points des bords.
- Vers le haut ou le bas, le pouce fait défiler la liste sous le pointeur, et la ligne désignée prend la sélection. Le pointeur ne court donc plus jusqu’au bord de la liste.
- Vers la gauche ou la droite, il longe la ligne, par exemple d’un titre à l’autre dans une rangée de la grille.
- Pour sortir, on tire au-delà du côté gauche ou droit. Après 48 points de pouce au-delà du bord, le pointeur passe 24 points en dehors et redevient le pointeur habituel.
- Par le haut ou le bas, il ne sort que si la liste avait déjà atteint ce bout. Un défilement qui atteint le bout s’y arrête ; un nouveau geste au-delà fait sortir.
- Un pouce qui dévie un peu ne fait pas les deux. Un geste une fois et demie plus vertical qu’horizontal fait seulement défiler ; un geste une fois et demie plus horizontal fait seulement longer la ligne.
- Un coup de pouce lance la liste, qui ralentit comme les listes du système. Toucher le pavé ou cliquer l’arrête.
- Le clic appuie sur la ligne désignée, comme avant : sur une chaîne, il la regarde.
- Le pointeur ne désigne jamais une ligne coupée par le haut ou le bas de la liste. Il prend la ligne entière la plus proche.

### Plus de choix pour le pointeur

Ces choix se trouvent dans Réglages › Télécommande › Pointeur :

| Réglage | 0.9.9 | 0.9.8 |
|---|---|---|
| Forme | Flèche, Main, Rond, Anneau, Viseur, Halo | Flèche, Rond |
| Couleur | Blanc, Noir, Cyan, Jaune, Rose, Vert | blanc seulement |
| Taille | Très petit (26 points), Petit (34), Normal (44), Grand (58), Très grand (76), Géant (100) | Petit, Normal, Grand |
| Vitesse | Très lente (×0,5), Lente (×0,7), Normale, Rapide (×1,45), Très rapide (×2) | Lente, Normale, Rapide |
| Accélération | Aucune, Normale, Forte | celle qu’est devenue « Normale », sans choix |

- **Accélération :**
  - Aucune : le pointeur va aussi loin que le pouce, lent ou rapide ;
  - Normale : comme en 0.9.8, de ×0,75 au ralenti à ×2 d’un geste vif ;
  - Forte : de ×0,6 à ×3, un coup de pouce traverse l’écran.
- Un aperçu montre le pointeur et le pointeur de défilement tels qu’ils sont réglés.
- Les choix faits en 0.9.8 restent valables.
- Chaque forme est dessinée une fois par réglage. Son ombre suit son contour, sans calcul d’ombre à chaque image. La main est un symbole du système, détouré et ombré d’avance.

### Revenir au mode classique depuis les Réglages

- En 0.9.8, en mode souris, le clic du pointeur sur « Classique » (Réglages › Télécommande) ne faisait rien. Le pointeur ne connaissait pas les deux tuiles du mode : il prenait ce clic pour un clic dans le vide. Seul un appui long sur Lecture/Pause ramenait la télécommande classique.
- Désormais, le clic choisit Classique : le pointeur disparaît, la sélection reste sur la tuile, et la bulle « Mode classique » le confirme.
- La bulle dit maintenant chaque changement de mode, quelle qu’en soit la cause : la tuile ou Lecture/Pause maintenue.

## Exécuté

| Vérification | Résultat |
|---|---|
| Vérification de types : Mac et banc du Mac, tvOS, tvOS du banc, parcours de la télécommande, variante App Store pour tvOS, et iPhone et iPad (simulateur) | Aucune erreur. |
| Tests du cœur (`swift test`) | 207 tests, aucun échec. |
| Banc Apple TV ciblé, simulateur Apple TV 1080p sous tvOS 27.2 | Les 6 parcours concernés, rejoués avant les correctifs du banc : 4 réussis. Après les correctifs, les 2 autres réussissent (voir plus bas). |
| Banc Apple TV complet (`scripts/test-tvos-catalog-ui.sh`) | À compléter. |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 95 captures et 29 scénarios de touches, en 6 min 47. Comme en 0.9.8, ce mode laisse de côté les scénarios de la recherche qui demandent la fenêtre active. |

## Ce que la vérification a trouvé

- **Le parcours du bord droit lisait mal son propre résultat.** Il évaluait son critère sur un texte au lieu de l’élément d’interface, et XCTest s’arrêtait sur une exception avant le premier appui. L’application n’était pas en cause. Corrigé dans le test : au passage suivant, Droite après Favoris est revenue sur « Cinéma ».
- **Le parcours des Réglages cherchait la tuile « Halo » à l’écran.** Sur un téléviseur 1080p, la section Pointeur commence au pied de la page, et ses tuiles sont dessous. Le pointeur du banc pousse désormais la page vers le bas jusqu’à elles. Il choisit « Halo », puis remonte la page jusqu’à « Classique ».
- **Le banc repartait des réglages du pointeur laissés par le parcours précédent.** Il les remet désormais à leur valeur par défaut à chaque lancement, comme il le faisait déjà pour le mode de la télécommande et le thème du dock.
- **Le modèle du dock avait reçu un paramètre de retour à gauche qu’aucun écran n’utilisait.** Seule l’Apple TV revient à gauche, et elle le fait depuis ses bandes de bord. Le paramètre est retiré ; seul reste le calcul de la hauteur (`DeskWrap`), testé.

## Ce que les bancs vérifient de nouveau

- **Le bord droit**, à la télécommande. Depuis la quatrième chaîne, Droite mène à Regarder, puis à Favoris. Après une pause, Droite revient à gauche, hors du dock, à moins d’un cinquième d’écran de la hauteur quittée. Capture : `edges-04-right-comes-round`.
- **La liste au pointeur.** Le pointeur entre dans la liste des chaînes et devient le pointeur de défilement. Le pouce vers le bas fait défiler la liste pendant que le pointeur garde sa hauteur : la sélection passe de la 4e à la 10e chaîne. Tiré vers la gauche, le pointeur sort de la liste. Il y revient, et son clic regarde la chaîne désignée. Capture : `pointer-list-01-scroll-pointer`.
- **Les Réglages du pointeur.** Le pointeur pousse la page jusqu’aux formes et choisit « Halo ». Il remonte sur « Classique » et le clique : la télécommande redevient classique, et une bulle le dit. Captures : `pointer-remote-01-shapes`, `pointer-remote-02-classic-key` et `pointer-remote-03-classic`.
- **Les tests du cœur :**
  - les nouveaux choix, avec les anciennes valeurs gardées ;
  - les trois accélérations ;
  - le partage des axes ;
  - la sortie par les côtés et par un bout déjà atteint ;
  - le retour à gauche à la même hauteur.

## Non vérifié

- **Une vraie Apple TV.** Comme David l’a demandé, les essais se font au simulateur. La 0.9.9 n’est installée sur aucun appareil. Le pavé tactile d’une vraie télécommande n’a donc pas été essayé : ni les glissements, ni les coups de pouce, ni la vitesse ou l’accélération ressenties. Le banc déplace le pointeur par des appels internes.
- **La liste lancée d’un coup de pouce.** Aucun parcours ne la lance.
- **Le pointeur de défilement ailleurs que sur la liste des chaînes** : sur la grille des films et des séries, et sur les colonnes. Aucun parcours ne l’y emmène.
- **Les autres formes et couleurs du pointeur à l’écran.** Les captures montrent la flèche blanche, le halo blanc et le pointeur de défilement. Les autres formes ne se voient que dans les tuiles des Réglages (`pointer-remote-01-shapes`).
- **Le retour à gauche avec un autre emplacement du dock** (masqué, en haut, à gauche, sous la colonne) : seul le dock en bas est parcouru.
- **iPhone et iPad** : rien n’y change. La vérification de types passe ; seule la CI les compile entièrement.
- **La CI de GitHub** : celle de la 0.9.9 part avec son envoi, et son résultat n’est pas dans cette page.

## Limites connues

- **Sur le Mac, le clavier ne revient pas à gauche** : Droite au bord droit mène toujours à l’icône de l’écran, dans le dock. Pour revenir à gauche, il faut savoir où se tient chaque contrôle à l’écran. L’Apple TV le sait pour son pointeur ; le Mac ne le suit pas, et le suivre coûterait à chaque image.
- Avec le dock masqué, seul le bord droit mène quelque part. Une flèche vers un autre bord où rien ne se tient ne fait rien.
- Une page des Réglages n’est pas une liste. Le pointeur la fait défiler comme avant, en poussant contre son bord.
