# Décors FLUX : cinéma, vidéoclub et salon

Les dix-huit images livrées sont les rendus de scènes 3D produites par
`bake_rooms.py`. Le script construit les volumes, le mobilier, les lumières,
les affiches graphiques originales et les matériaux par calcul. Il ne charge
aucun modèle 3D, aucune photographie, aucune texture externe et aucune image IA.

| Espace | Recette | Ressource |
|---|---|---|
| Films | Hall de cinéma, affiches éclairées, velours, laiton, entrée de salle avec sièges | `cinema-<theme>.jpg` |
| Séries | Vidéoclub avec rayonnages, coffrets, tables de présentation et enseigne | `videoClub-<theme>.jpg` |
| TV | Salon avec canapé, fauteuil, téléviseur, console, fenêtres, tapis, lampe et plante | `livingRoom-<theme>.jpg` |

Les six thèmes sont `neo90`, `midnight`, `vintage70`, `artDeco`, `zen` et
`future`. La palette et l'éclairage changent, ainsi que certains éléments
architecturaux : globes ambrés, couronnes Art déco, portiques lumineux ou
baffles en chêne. Le cadrage reste fixe pour préserver l'espace de navigation.

## Reconstruction

Blender 4.3.2 a produit les images livrées avec Cycles CPU, 24 échantillons,
6 rebonds maximum, graine `82026`, AgX et un débruitage HDR OpenImageDenoise.
Les JPEG sont en 1920 × 1080, qualité 93. Le manifeste donne les empreintes
SHA-256, les dimensions, le temps de fabrication et le nombre d'objets.

Avec une distribution Blender contenant OpenImageDenoise :

```sh
blender -b -t 6 --python scripts/rooms/bake_rooms.py -- --all --samples 24
python3 scripts/rooms/verify_rooms.py
```

Certaines distributions système de Blender excluent le débruiteur. Dans ce
cas, installer `oidn==0.2.1`, `numpy` et `pillow` dans un Python de fabrication
puis désigner cet interpréteur avec `FLUX_DENOISE_PYTHON`. Le débruitage tourne
dans un processus indépendant pour éviter les conflits de bibliothèques TBB
avec Blender. `FLUX_DENOISE_PYTHONPATH` et `FLUX_DENOISE_LIBPATH` permettent de
désigner, si nécessaire, le répertoire des modules et celui des bibliothèques
natives de cette installation. Aucun de ces composants n'est embarqué dans
l'application.

```sh
FLUX_DENOISE_PYTHON=/chemin/vers/python3 \
blender -b -t 6 --python scripts/rooms/bake_rooms.py -- --all --samples 24
```

Pour une seule combinaison :

```sh
blender -b -t 6 --python scripts/rooms/bake_rooms.py -- \
  --kind cinema --theme neo90 --width 960 --height 540 --samples 16
```

Ce dernier exemple remplace le fichier correspondant par un aperçu : relancer
la fabrication complète avant de distribuer l'application. `verify_rooms.py`
refuse les images réduites, les ressources manquantes, les doublons et toute
empreinte différente du manifeste. Les calculs utilisent une graine fixe ;
des versions différentes de Blender, des bibliothèques ou du matériel peuvent
produire de légères différences numériques.

## Utilisation dans l'application

Seuls les JPEG précalculés sont affichés. Blender, Cycles et OIDN ne s'exécutent
pas sur le Mac, l'iPhone ou l'Apple TV de l'utilisateur. Les scripts sont des
outils de fabrication inclus dans les sources. Les pochettes manipulables
restent des objets 3D natifs séparés. Le backend de rendu de ces décors est
Cycles ; ce n'est pas une exécution du backend GPU FERRO.
