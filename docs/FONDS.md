# Fonds des écrans

Depuis la 0.9.3, chaque écran a ses propres images : TV, Recherche et Réglages en ont trois, Films et Séries deux. Elles passent l’une après l’autre derrière l’écran. L’accueil montre celles de l’écran qu’ouvre son icône sélectionnée. Trois autres ont été dessinées pour la boutique. Les 18 décors des versions précédentes (`FluxIPTVMac/RoomBakes`) sont retirés : un choix enregistré qui en contenait revient aux images de l’écran.

## Les seize images

Elles sont dans `FluxIPTVMac/Backdrops/`, et leurs noms dans `FluxBackdropLibrary.art` (`Sources/FluxIPTVCore/SpaceAppearance.swift`).

| Écran | 1 | 2 | 3 |
|---|---|---|---|
| TV | Salon néon 90 (`tv-1`) | Loft panoramique (`tv-2`) | Régie de diffusion (`tv-3`) |
| Films | Grande salle (`films-1`) | Drive-in au crépuscule (`films-2`) | — |
| Séries | — | Coin binge-watching (`series-2`) | Bibliothèque des séries (`series-3`) |
| Recherche | Observatoire (`recherche-1`) | Archives infinies (`recherche-2`) | Phare dans la nuit (`recherche-3`) |
| Réglages | Cabine de projection (`reglages-1`) | Salle des machines (`reglages-2`) | Studio aux boutons (`reglages-3`) |
| Boutique | Boutique néon (`store-1`) | Galerie de verre (`store-2`) | Comptoir Art déco (`store-3`) |

Elles ont été dessinées par ChatGPT le 26 novembre 2026, livrées en 1672 × 941, puis agrandies en 3840 × 2160 et enregistrées en JPEG, 17 Mo pour les dix-huit livrées. Elles sont sombres, sans texte, sans logo et sans personne. Les trois de la boutique sont arrivées dans un second envoi, le même soir ; les quinze autres y étaient identiques à l’octet près.

Les images de la boutique ne sont celles d’aucun écran : le studio d’apparence les montre derrière ses onglets, comme la vitrine d’un magasin, et tout écran peut les prendre. L’écran Boutique, quand il existera, les aura pour fond.

Deux sont retirées le soir même, à la demande de David devant son téléviseur : le hall Art déco des Films (`films-3`), une entrée, alors qu’il veut « une salle avec sièges et grand écran » ; le vidéoclub des Séries (`series-1`), « pas top ». Les fonds à redessiner, écran par écran, sont dans [FONDS-A-DESSINER.md](FONDS-A-DESSINER.md).

## Ce que l’app en fait

- Une image est décodée hors du fil principal, à la taille où elle est montrée : 1920 pixels de large au plus sur Apple TV.
- La suivante d’un diaporama est décodée quatre secondes avant son tour, puis vient en fondu. Le studio passe plus vite d’une image essayée à l’autre.
- L’ordre « Au hasard » change à chaque tour, sans reprendre l’image qui a fini le tour d’avant. Il est le même sur tous les appareils, car il se calcule à partir de l’heure.
- Les écrans voisins restent chargés derrière celui qui est affiché : pointer une icône de l’accueil montre aussitôt ses images.
- Le préréglage « Fluide » coupe les fonds : aucune image n’est décodée. Rien n’est dessiné derrière une vidéo.

## Ajouter une image ou une collection

1. Le fichier : JPEG 16:9 en 3840 × 2160, dans `FluxIPTVMac/Backdrops/`, sous un nom court et stable (`tv-4.jpg`).
2. Son entrée dans `FluxBackdropLibrary.art`, avec son titre et l’écran pour lequel elle a été dessinée (aucun pour la boutique).
3. `swift test` vérifie que chaque image nommée est livrée, et que le dossier n’en contient pas d’autres.

Les projets Xcode prennent le dossier entier : il n’y a pas à les régénérer pour une image de plus.

Le studio range les images par collection : « Fonds dessinés · TV », « Fonds dessinés · Boutique », « Docks · Rétro »… Une collection pourra porter un prix quand l’app sera publiée, et s’essayer gratuitement comme aujourd’hui.

## Pour dessiner d’autres fonds

Les règles données à ChatGPT, à reprendre pour une nouvelle collection :

- Paysage 16:9, dans la plus grande résolution possible. Rendu 3D cinématographique proche du photoréalisme, caméra à hauteur des yeux, lumière de nuit travaillée.
- L’interface se pose par-dessus : le centre, le tiers gauche et la bande du bas restent sombres et calmes. La lumière et les détails vont sur les bords et au fond.
- Aucun texte, aucune lettre, aucun chiffre, aucun logo, aucune marque, aucune enseigne lisible, aucune personne.
- Une collection forme une famille : même soin de la lumière, contrastes doux, pas de couleurs criardes.
