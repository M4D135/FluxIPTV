# Décors FLUX : dix-huit intérieurs en 4K

Les dix-huit images de la version 0.8.6 sont calculées à **3840 × 2160** à partir
de scènes 3D originales construites par `bake_rooms.py`. Le script crée les
volumes, le mobilier, les lumières, les affiches graphiques et les matériaux
procéduraux. Il ne charge aucun modèle, photographie ou texture externe.
Les images ne sont ni agrandies depuis des rendus HD ni générées par IA.

| Espace | Architecture commune | Ressource |
|---|---|---|
| Films | Hall de cinéma, affiches éclairées, entrée de salle et sièges | `cinema-<theme>.jpg` |
| Séries | Vidéoclub, rayonnages, coffrets, îlots et enseigne | `videoClub-<theme>.jpg` |
| TV | Salon, écran au repos, sièges, table, livres et lumière de fenêtre | `livingRoom-<theme>.jpg` |

## Six constructions différentes

Les thèmes changent la silhouette du décor et sa construction, en plus des
matériaux et de la couleur. Les salons ont chacun leur propre implantation.
Les halls et vidéoclubs partagent leur usage, mais reçoivent des portiques,
plafonds, sols et îlots propres à chaque style.

| Thème | Salon TV | Hall et vidéoclub |
|---|---|---|
| `neo90` | Loft en briques, fermes métalliques, salon décalé, néons cyan et rose | Charpente exposée, allées contrastées et lignes lumineuses |
| `midnight` | Penthouse vitré, silhouettes de ville, monolithe TV et tables gigognes | Piliers de pierre sombre, plinthes flottantes et longues fentes lumineuses |
| `vintage70` | Canapés bas en U, travertin, alcôves arrondies, globes et poutres | Poutres en bois, portails arrondis, globes opalins et îlots circulaires |
| `artDeco` | Arches et cannelures en laiton, lustre, tissu émeraude et plafond à ressauts | Grands portiques à gradins, éventails dorés et sol de pierre incrusté |
| `zen` | Claustras en chêne, shoji, lampe en papier, sièges bas et table organique | Canopée de bois, écrans de papier, plantes et îlots espacés |
| `future` | Nervures facettées, éclairage encastré, console flottante et table hexagonale | Portiques structurels facettés, lignes de sol et îlots hexagonaux |

Les coussins disposent de bords arrondis et de passepoils géométriques. Les
matériaux du bois, du tissu, de la pierre et du métal sont séparés. Les livres,
revues, vases et autres accessoires restent limités pour préserver la lisibilité
des commandes et du catalogue superposés par l’application.

## Reconstruction locale

La production utilise Blender **4.3.2**, Cycles CPU, 24 échantillons avec seuil
adaptatif, 6 rebonds maximum, graine `82026`, AgX et OpenImageDenoise en HDR.
Les JPEG 4K sont enregistrés en qualité 93. Le manifeste conserve les dimensions,
empreintes SHA-256, temps de fabrication, nombre d’objets, version de Blender
et empreintes des sources du générateur.

Avec une distribution officielle de Blender contenant OpenImageDenoise :

```sh
blender -b -t 8 --python scripts/rooms/bake_rooms.py -- --all
python3 scripts/rooms/verify_rooms.py
python3 scripts/rooms/make_preview.py
```

Les aperçus utilisent une destination distincte et ne remplacent pas les
ressources distribuées :

```sh
blender -b -t 8 --python scripts/rooms/bake_rooms.py -- \
  --kind livingRoom --all-themes --width 960 --height 540 \
  --samples 24 --output-dir /tmp/flux-room-previews
```

Pour une seule combinaison, remplacer `--all-themes` par `--theme artDeco`.
L’option `--save-scene` conserve également le fichier Blender de la combinaison
rendue dans la destination choisie.

Certaines distributions système excluent OpenImageDenoise. Le recours facultatif
à `oidn==0.2.1`, `numpy` et `pillow` reste disponible dans un interpréteur externe,
désigné par `FLUX_DENOISE_PYTHON`. `FLUX_DENOISE_PYTHONPATH` et
`FLUX_DENOISE_LIBPATH` permettent d’indiquer ses modules et bibliothèques.
Le débruitage est alors isolé de Blender afin d’éviter les conflits de TBB.
Ces outils ne sont pas embarqués dans l’application.

## Fabrication parallèle

Le workflow `.github/workflows/room-bakes.yml` construit les dix-huit combinaisons
en jobs séparés. Il télécharge Blender 4.3.2 depuis le site officiel et vérifie
l’archive avec le fichier SHA-256 publié à la même adresse. Chaque job livre un
JPEG et son compte rendu de rendu.

Le job final emploie `assemble_rooms.py` pour refuser tout mélange de versions de
Blender, paramètres ou sources. Il vérifie les dix-huit images, puis publie
l’artefact `FluxIPTV-4K-RoomBakes`, comprenant les images, le manifeste et une
planche de comparaison. `verify_rooms.py` vérifie également que les sources
présentes correspondent aux empreintes enregistrées dans le manifeste.

```sh
python3 scripts/rooms/assemble_rooms.py \
  --input-dir /chemin/vers/les-rendus --output-dir FluxIPTVMac/RoomBakes
python3 scripts/rooms/verify_rooms.py
```

Le workflow répond à une publication sur `work/room-bakes-0.8.6` ou à un lancement
manuel. Il ne refabrique pas les décors à chaque compilation de l’application.
Les versions du matériel ou des bibliothèques de rendu peuvent introduire de
légères différences numériques même avec une graine fixe.

## Affichage dans l’application

L’application affiche les JPEG précalculés à une définition adaptée à la surface
et à l’échelle de l’écran, jusqu’à 3840 pixels. Blender, Cycles et OIDN restent des
outils de fabrication. Les boîtiers manipulables sont des objets 3D natifs séparés.
Le rendu de ces décors utilise Cycles ; il ne constitue pas une intégration du
backend GPU FERRO dans l’application.
