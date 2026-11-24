# FLUX 3D — architecture et provenance

Référence consultée : [FERRO 0.3.15](https://github.com/M4D135/FERRO/tree/a443359c4741a815f384278e6427a33758d79f2f), module [geometry.js](https://github.com/M4D135/FERRO/blob/a443359c4741a815f384278e6427a33758d79f2f/dist/ferro-runtime/modules/geometry.js), fonction `tube`. Le module web est pur et construit des triangles depuis une courbe Catmull–Rom, un repère transporté et des anneaux de sections circulaires. `ProceduralCinema.swift` en reprend les équations d'interpolation, le transport parallèle pour tube ouvert et l'orientation extérieure des triangles. Ce sous-ensemble Swift n'est pas une copie intégrale du moteur FERRO, ne réutilise pas son exécutable JS et ne prétend pas à la parité de rendu, de lissage, de matériaux ni de performances.

## Budget

- 3 recettes, couleurs par type de média, aucune texture requise pour la scène. Les jaquettes du fournisseur restent des images externes distinctes.
- Moins de 3 000 triangles par décor, projection perspective avec éclairage et tri en profondeur. Pas de simulation physique, de boucle de jeu, de WebKit, ni de dépendance 3D ajoutée.
- Rasterisation CoreGraphics sur tâche utilitaire, 960 × 540 (environ 1,98 Mio en RGBA). Cache NSCache : 3 entrées et cible de 8 Mio (limites indicatives). L'image générée n'est pas enregistrée sur disque. Le calcul ne se répète que sur changement de recette/type ou cache évincé.
- Catalogue : galerie native avec perspective des cartes pendant le défilement ; grille en alternative. Réduction des mouvements et de la transparence respectées. Fond du média avec chargement différé de 240 ms et taille maximale de 1 024 px, cache séparé de 16 Mio, réseau annulable.
- Vidéo : retrait de la scène et de l'arrière-plan du catalogue ; aucune boucle de décor, pas de flou du flux. Un travail court déjà commencé peut finir avant d'être annulé, sans conserver de résultat obsolète.

## À qualifier sur matériel Apple

Compiler les trois schémas ; tester les interactions souris, Siri Remote et touch ; ouvrir et quitter un flux HLS puis un épisode MKV ; vérifier les transitions AVPlayer/VLC, la consommation via Instruments, et le mode de récupération en cas de crash. L'objectif est un menu très léger et agréable, non un moteur de jeu actif pendant le décodage. Pour des scènes animées plus complexes, un futur port Metal devra être évalué séparément avant intégration.
