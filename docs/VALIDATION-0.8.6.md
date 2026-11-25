# FLUX IPTV 0.8.6 — Rayons, coffrets et aperçu TV

Version du 25 novembre 2026, build 19, issue de la base 0.8.5 `20046ef58e08c1531fadb30d38c7d3baf6f33387`.

## Comportements de cette version

Les boîtiers du catalogue sont rapprochés comme dans un rayon. La boîte choisie avance vers le premier plan, avec un cadrage plus grand ; ses voisins restent de vrais objets volumétriques derrière elle. Le cadrage tient compte de la pose et du couvercle, sans réduire le titre principal pour faire entrer tous les voisins. Films et séries utilisent un DVD à partir de 2000, une VHS avant 2000, et un DVD lorsque l’année des métadonnées n’est pas exploitable.

Un coffret présente une rangée de boîtiers de saisons. La sélection fait ressortir un boîtier ; Valider ouvre ses épisodes. Les numéros fournis, dont les spéciaux de saison 0, sont conservés. Les grandes collections utilisent une fenêtre de huit boîtiers qui suit le choix courant.

La navigation de l’inspecteur distingue rotation, sélection et lecture. Gauche/Droite tourne ; un double appui rapide change de titre. Haut sélectionne le widget d’aperçu, puis le bouton de lecture situé au-dessus. Valider active la cible. Lecture lance directement le film ou l’épisode indiqué. Bas sélectionne la barre compacte Reposer / Actions / Favoris. Retour/Menu repose la boîte depuis ses sous-modes. L’aide et les bordures de sélection indiquent ce contexte.

Le lecteur de bande-annonce conserve son identité et sa position durant une rotation. L’orientation effectivement rendue, avec une petite hystérésis au profil, détermine la pause sur le recto et la reprise au verso. Une pause manuelle et une vidéo terminée ne sont pas annulées par une rotation. L’aperçu d’une série ouverte suit le couvercle, et non le corps resté derrière lui. La WebView conserve une taille logique stable, tandis que sa projection suit le cadre physique.

La TV reçoit un bandeau de modules flottants, des catégories à gauche sur les grands écrans, une recherche de catégories et une recherche de chaînes visibles, ainsi que des lignes compactes et paginées. Un unique AVPlayer prévisualise la chaîne choisie après un délai stable. Le délai TV vaut 3 secondes par défaut et se règle sur 1/3/5/10 secondes indépendamment des films/séries, qui gardent 5 secondes par défaut. L’aperçu est muet au départ, avec commande de son, et s’arrête avant la lecture principale.

Les 18 décors sont des rendus natifs 3840 × 2160 de géométries procédurales Blender/Cycles. Les six thèmes changent architecture, mobilier et éclairage. Les images sont précalculées avec OpenImageDenoise ; l’application adapte leur décodage à l’écran et ne calcule pas une pièce 3D en continu. Ce travail n’intègre pas le runtime FERRO.

## Vérifications rattachées au commit

Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) produit des résultats distincts pour chaque commit. Le statut de ses jobs, et non la seule présence d’une archive, indique la réussite de la livraison.

- Tests Swift du cœur : format VHS/DVD, dimensions et cadrage, navigation de l’inspecteur, doubles appuis bornés, répétitions, orientation du verso, fenêtre de saisons, navigation entre catégories et chaînes, délais indépendants et tests existants.
- Contrôle des déclarations SwiftUI et du projet Xcode généré, qui inclut les nouveaux fichiers partagés.
- Intégrité des 18 JPEG : dimensions 4K réelles, empreintes distinctes, tailles, déclaration Cycles/OIDN et empreintes des scripts ayant créé les ressources.
- Compilations séparées de macOS universel, iOS Simulator et tvOS Simulator avec Xcode 26.3, pour compiler réellement les chemins Liquid Glass.
- Vraie WKWebView et fournisseur IFrame local : états du lecteur, commandes, orientation et pause/reprise, fin de vidéo, conservation de l’instance entre hôtes, erreurs et libération.
- Vrai AVPlayer et vidéo locale créée par AVFoundation : délai TV, remplacement et stabilité de la sélection, annulation, sourdine, repli d’URL et libération du lecteur.
- Vrai renderer SceneKit : recto/verso, projection et UV de l’aperçu, hit test du boîtier de saison, aperçu attaché au couvercle ouvert, captures dans les diagnostics.
- Archives d’applications et pack complet des sources du commit exécuté, avec identifiant de commit et empreinte SHA-256.

Le workflow de préparation [Render 18 original 4K interiors](https://github.com/M4D135/FluxIPTV/actions/workflows/room-bakes.yml) rend les combinaisons univers/thème indépendamment, puis assemble uniquement des résultats dont la version du moteur, les paramètres et les empreintes des générateurs concordent.

## Limites pratiques

Les tests natifs utilisent des vidéos et fournisseurs locaux contrôlés. Ils ne démontrent pas l’accès à un serveur IPTV particulier, la lecture d’une vidéo YouTube distante, les refus d’intégration ou les performances du réseau de l’utilisateur. Les gestes d’une Siri Remote physique, le rendu perceptuel de Liquid Glass et la fluidité sur chaque appareil demandent un essai sur le matériel correspondant.

Un aperçu TV dont le format n’est pas pris en charge par AVPlayer reste indisponible ; la lecture principale conserve ses moteurs existants. Aucun programme EPG n’est ajouté. Les titres sans bande-annonce ne reçoivent pas une vidéo inventée. Sur tvOS, les vidéos directes sont intégrées et YouTube conserve son ouverture explicite sur iPhone par QR code.

Les images 4K sont les fonds distribués, pas des captures de l’interface complète. Le lecteur et les boîtes restent natifs. Les builds Mac des Actions ne sont pas notariés pour distribution ; les builds iOS/tvOS ciblent les simulateurs. Le projet complet permet une compilation et une signature sur les appareils de l’utilisateur.
