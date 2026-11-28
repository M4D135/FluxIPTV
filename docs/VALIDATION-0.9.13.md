# Validation de FLUX IPTV 0.9.13 — build 54

La 0.9.13 rend au pointeur de l’Apple TV les touches du haut de la colonne des Réglages. En mode souris, quand le dock est masqué, Retour et Accueil se tiennent en haut de cette colonne : le pointeur s’y posait sans leur donner la télécommande, et un clic n’y faisait rien. Il les sélectionne désormais, et un clic y appuie, comme sur la barre ou en haut de la colonne d’un catalogue. Il en va de même de Fermer, en haut des réglages ouverts pendant la lecture.

David l’a signalé le 28 novembre 2026, photo du téléviseur à l’appui : « mode pointeur impossible de cliquer sur precedent ou home , boutons du haut inactifs avec pointeur ».

Pour le reste, les validations de la 0.9.12 ([VALIDATION-0.9.12.md](VALIDATION-0.9.12.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 28 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- au simulateur Apple TV 4K (4e génération), en 1080p, sous tvOS 27.2 ;
- sur l’état final des sources.

## Ce qui change pour la vérification

- **La cause.** Le pointeur ne déplace pas la sélection de lui-même : chaque touche qui l’accepte se déclare sous un nom, et le pointeur donne la télécommande à celle qu’il survole ; un clic appuie sur celle qui l’a. En haut de la colonne d’un catalogue, Retour, Accueil et la touche qui replie la colonne se déclaraient. En haut de la colonne des Réglages, le même en-tête ne recevait pas de quoi se déclarer : le pointeur passait sur Retour, Accueil et Fermer sans rien leur donner.
- **La correction.** La colonne des Réglages donne à son en-tête la place où ranger la sélection, comme le fait celle des catalogues : Retour, Accueil et Fermer se déclarent au pointeur sous leurs noms (`desk-back`, `desk-home`, `desk-close`). Le Mac n’a pas de pointeur de ce genre ; son en-tête ne change pas.
- **La télécommande sans le pointeur.** La correction ne touche que ce que le pointeur voit des touches ; les parcours aux flèches du banc passent tous, comme en 0.9.12.

## Exécuté

| Vérification | Résultat |
|---|---|
| Vérification de types : Mac (production, et avec le banc du Mac), tvOS, tvOS du banc, parcours de la télécommande, variante App Store pour tvOS, et iPhone et iPad (simulateur) | Aucune erreur. |
| Tests du cœur (`swift test`) | 230 tests, aucun échec. |
| Le nouveau parcours seul (`FLUX_TVOS_FLOWS`), sur les sources corrigées | Réussi en 26,7 s. Le pointeur passe par Accueil et se pose sur Retour, qui prend la télécommande ; le clic quitte les Réglages pour l’accueil. Il se pose ensuite sur Réglages dans la barre, que le clic rouvre, puis sur Accueil, dont le clic ramène à l’accueil. Sur les réglages posés sur l’image, il passe par une ligne de la colonne et se pose sur Fermer, dont le clic ferme les réglages. |
| Le même parcours, sur l’en-tête de la 0.9.12 (`PlaybackSettingsView.swift` de `a29ad61`, le reste corrigé) | Échec en 72,9 s, comme attendu : le pointeur n’a donné la télécommande ni à Accueil ni à Retour (`miss:desk-home`, `end=miss:desk-back`). Le parcours voit donc le défaut que David a photographié. |
| Banc Apple TV complet (`scripts/test-tvos-catalog-ui.sh`), Apple TV 4K (4e génération) en 1080p sous tvOS 27.2 | Les 39 écrans, tous valides (41 captures) ; les 34 parcours, le nouveau compris, sans échec, en 23 min 01 ; 28 min 48 en tout. Les six parcours de mesure ne jouent qu’à la demande et n’ont pas été joués. |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 101 captures et 32 scénarios de touches, aucun échec ; 5 min 12 de la première capture à la dernière. Comme en 0.9.12, ce mode laisse de côté les scénarios de la recherche qui demandent la fenêtre active. |

## Ce que les bancs vérifient de nouveau

- **Le pointeur en haut des Réglages.** Un parcours lance les Réglages avec le pointeur, sans le dock (`FLUX_UI_POINTER=1`, `FLUX_UI_DOCK_HIDDEN=1`) : le pointeur doit donner la télécommande à Accueil puis à Retour, et le clic sur chacun doit faire ce qu’il dit. Relancé sur les réglages posés sur l’image, il doit la donner à Fermer, dont le clic ferme les réglages. Trois captures en gardent la trace : `pointer-header-01-back`, `pointer-header-02-home` et `pointer-header-03-close`.
- **Le balayage du pointeur.** Le banc de l’application mène le pointeur à son propre rythme, sans pouce : les Réglages (`settings`) et les réglages pendant la lecture (`player-settings`) ont désormais leur balayage, qui note chaque touche atteinte ou manquée.

## Non vérifié

- **Sur une Apple TV.** Rien n’a été installé sur une Apple TV pour cette version : la correction n’a pas été vue sur le téléviseur de la photo.
- **Le pointeur au pouce.** Le banc mène le pointeur lui-même, d’une touche à l’autre ; le geste sur la surface de la télécommande n’y est pas joué.
- **iPhone et iPad** : ils n’ont pas ce pointeur. La vérification de types passe ; seule la CI les compile entièrement.
- **La CI de GitHub** : celle de la 0.9.13 part avec son envoi, et son résultat n’est pas dans cette page. Celle de la 0.9.12 (`a29ad61`) n’avait pas fini à l’écriture de cette page : sur la branche comme sur main, les écrans et les parcours de l’Apple TV tournaient encore sur les machines hébergées, et toutes les autres tâches étaient passées.

## Limites connues

- **Les couleurs des écrans** (Réglages › Interface) donnent toujours aux thèmes leurs deux couleurs, et le fond uni quand un écran n’a pas d’image ; les ranger dans le thème reste pour une prochaine version.
- **Le pied de page au clavier du Mac.** Bas y passe d’une page à l’autre sans s’arrêter au pied, qui sert au pointeur.
