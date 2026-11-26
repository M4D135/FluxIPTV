# Validation de FLUX IPTV 0.9.0 — build 38

La 0.9.0 donne au Mac et à l’Apple TV la même interface de bureau : accueil, dock en bas au centre, colonne de navigation, télévision en trois colonnes, fiches et listes d’un titre en verre, commandes de lecture et langues, liste de zapping, réglages en verre appliqués dès qu’ils sont choisis, filtre par langue pour les films et les séries. Retour y est le Précédent d’un navigateur ; au clavier du Mac il montre d’abord la boussole des zones. iPhone et iPad conservent la disposition de la 0.8.9. Ce rapport distingue ce qui a été exécuté de ce qui ne l’a pas été.

Les vérifications ci-dessous ont été faites les 25 et 26 novembre 2026 sur un Mac Apple Silicon, macOS 27.2, Xcode 27.2 (Swift 6.4.2), sur l’état final des sources. **Le résultat de GitHub Actions sur le commit livré reste la référence** : le workflow compile avec Xcode 26.3 sur un Mac Intel et teste le cœur sous Linux avec Swift 6.2.

## Exécuté

| Vérification | Résultat |
|---|---|
| `swift test` | 160 tests du cœur réussis, dont 23 nouveaux |
| `scripts/check-state-declarations.sh` | aucune erreur |
| `scripts/rooms/verify_rooms.py` | 18 décors vérifiés, inchangés |
| `scripts/generate-xcodeproj.py` | les deux projets générés sont à jour |
| Compilations | macOS, iOS Simulator, tvOS Simulator et tvOS appareil |
| `scripts/test-catalog-ui.sh` en mode local, avec la galerie | 37 captures de la vraie interface du Mac ; les six parcours de touches aboutissent |
| `scripts/test-tvos-catalog-ui.sh` | vingt-quatre scénarios natifs, trois démarrages à froid et onze parcours XCUIRemote réussis |
| Application réelle sur le Mac, source Xtream enregistrée | voir « Essai réel » |

### Tests du cœur ajoutés

- **Dock** : ordre enregistré (entrées inconnues ou répétées écartées, nouvelles destinations ajoutées), déplacement d’une icône, identifiants de focus ; agrandissement nul sans pointeur, maximal sous lui, cellules jamais superposées et sans saut sur un balayage complet ; navigation entre le dock et l’écran pour chaque bord.
- **Historique de Retour** : comme dans un navigateur, les écrans se dépilent dans l’ordre où ils ont été ouverts, jusqu’à l’accueil ; un écran ouvert deux fois compte deux étapes ; revoir l’écran déjà affiché n’en ajoute pas ; un long va-et-vient oublie ses plus vieilles étapes et finit quand même à l’accueil ; quitter un écran jamais enregistré ramène au précédent.
- **Zones** : pour chacun des cinq emplacements du dock et chaque combinaison de zones présentes, toute zone est atteignable depuis toute autre ; les voisinages suivent la disposition de l’écran ; Tab parcourt les zones dans l’ordre de lecture.
- **Navigation du bureau** : passages entre la colonne, la grille, les rangées du haut et les actions voisines de l’aperçu, y compris une dernière rangée incomplète, un catalogue vide, et le lien entre le haut de la colonne et les commandes placées au-dessus d’elle.
- **Langue des films et des séries** : étiquettes de titre et de catégorie reconnues, mots ordinaires et marques écartés, seuil de trois titres pour une étiquette comme pour une langue, filtrage du catalogue, validation de la langue mémorisée.

Un test existant affirmait que le pays ne filtre jamais les films ni les séries. Il vérifie désormais la règle voulue : chaque type a un filtre, le pays pour les chaînes et la langue pour les titres, et un code de pays mémorisé pour des films est abandonné.

### `swift test` sur Mac

Avec le SDK macOS 27.2, `import Foundation` ne fournit plus à lui seul les initialiseurs ni l’égalité de `CGRect`. Trois fichiers du cœur importent maintenant CoreGraphics quand il existe. La suite ne compilait pas sur ce Mac avant cette correction ; le workflow ne le voyait pas, ses tests du cœur tournant sous Linux.

### Captures Mac

Le banc dessine la vraie `ContentView` dans une fenêtre native avec un catalogue local : accueil, télévision, films, fiche film, rayon des saisons, fiche série, favoris, réglages des sources et du dock, réglages et liste de zapping posés sur le lecteur, bandeau d’une chaîne sur son image nue, boussole des zones ; puis, pour la galerie, les cinq thèmes du dock avec le pointeur sur une icône, les quatre autres emplacements, l’accueil avec le pointeur sur Films et sur Séries, et le filtre par langue. Les deux fiches satisfont le contrôle existant : un seul grand boîtier entièrement visible, la commande de lecture présente, aucun lecteur ni vue web.

Six scénarios envoient à l’écran les touches d’une télécommande par le même traitement que le clavier, et échouent si la sélection n’arrive pas où elle doit :

| Touches | Sélection attendue |
|---|---|
| Retour, Bas | la destination en cours, dans le dock |
| Retour, Haut, Droite | Actualiser |
| Retour, Bas, Gauche, Gauche | le bouton Retour, à gauche du dock |
| Retour, Retour | l’accueil |
| Dans le lecteur : Droite trois fois, OK, Bas, Retour | la touche Langues, son panneau ouvert sur l’audio en cours puis refermé |
| Sur l’image nue d’une chaîne : Haut, Haut, Bas | l’image garde les touches ; la deuxième chaîne est à l’écran, sous son bandeau, sans commandes |

Les commandes de lecture d’un direct et d’un film, les langues, les réglages du lecteur et la liste de zapping sont capturés au-dessus d’un décor qui tient lieu d’image. Le banc ne lit aucun flux : le contrôleur de lecture n’y reçoit que l’état publié d’un média qui joue — titre, position, pistes — sans ouvrir de connexion ni démarrer de moteur.

Ces captures ont été prises fenêtres hors écran, sans prendre le premier plan. **Les trois scénarios de focus de recherche, qui exigent la fenêtre active, n’ont pas été exécutés sur cette version.**

### Banc Apple TV

Le banc a été exécuté sur l’état final des sources, dans un simulateur qu’il crée (tvOS 27.2, Apple TV 4K à 1080p), avec le Liquid Glass actif comme dans l’application.

Vingt-quatre scénarios lancent l’application sur un écran et exigent que le focus natif soit sur le contrôle attendu, mesuré dans la fenêtre : l’accueil, la télévision, les films, les films d’un catalogue de 58 093 titres, la fiche d’un film, les listes d’un titre, le rayon des saisons, la saison 12 et son épisode 15, les commandes de lecture d’un direct et d’un film, les langues, les réglages pendant un flux, le bandeau d’une chaîne en direct puis en ouverture, la liste de zapping, les réglages, l’accueil sans source, le formulaire d’une source, deux recherches, la France, l’Espagne, les pays dans la colonne et la restauration d’une chaîne. Le formulaire d’une source doit tenir dans la zone sûre de l’écran, hors de toute vue défilante. Le bandeau d’une chaîne doit être seul sur l’image — aucune commande, aucune carte au milieu —, dans la zone sûre, large d’au moins la moitié de l’écran, au pied de celui-ci ; c’est alors l’image elle-même qui tient la télécommande.

Ce qui s’écrit sur l’image est lu avec des noms taillés comme ceux d’une vraie liste de lecture : un préfixe, un titre long, une marque de qualité (« PRISME: GRAND ÉCRAN FESTIVAL ᴿᴬᵂ »), des catégories qui portent leur pays (« DIRECT - FR| CINÉMA »). Les deux écrans du bandeau utilisent un catalogue de 24 665 chaînes, pour un numéro à cinq chiffres. Les catalogues précédents, aux noms courts et aux dix-huit chaînes, ne montraient ni les noms coupés ni les numéros repliés sur deux lignes.

Onze parcours passent par XCUIRemote, donc par le vrai moteur de focus :

- **Les flèches seules** : depuis la liste des chaînes, Haut mène au champ de recherche, Gauche à la colonne — sur « Toutes les chaînes », la ligne de ce qui est affiché, y compris depuis la quatrième chaîne, qui fait face à une autre ligne —, Droite ramène à la chaîne quittée puis à Regarder, Bas de là au dock, que les flèches parcourent jusqu’au bouton Retour, et Haut ramène dans l’écran.
- **Menu comme le Précédent d’un navigateur** : de l’accueil, la télévision s’ouvre avec la télécommande sur sa première chaîne ; puis les films, par le dock, sur leur premier titre ; puis la télévision de nouveau. Menu, depuis l’intérieur de la liste, revient aux films sur le titre laissé, sans panneau intermédiaire ; Menu encore, à la télévision ouverte en premier ; Menu enfin, à l’accueil.
- **Lecteur pendant un flux**, sur une lecture simulée dont les commandes se masquent comme en vrai : elles se retirent, OK les rappelle sur Pause ; Réglages ouvre ses panneaux sur la page Vidéo, qui garde la télécommande sept secondes, plus que le délai de masquage ; Bas affiche la page Réseau, Droite entre dans son contenu, Gauche revient sur elle ; Menu referme les panneaux sur la touche Réglages. Langues s’ouvre sur l’audio en cours, un autre choix s’applique, le panneau garde lui aussi la télécommande sept secondes, Menu le referme sur sa touche ; Menu quitte enfin la lecture pour la liste d’où elle est partie.
- **Zapping**, sur la cinquante-neuvième chaîne de cent dix, que le catalogue n’avait pas sélectionnée, la lecture simulée changeant de chaîne comme un moteur, flux en ouverture un instant puis en lecture : commandes masquées, Bas puis Bas changent de chaîne sous le seul bandeau, qui annonce la 58 puis la 57, l’image gardant la télécommande et les commandes ne revenant pas ; Bas encore mène à une chaîne morte, que le bandeau marque indisponible sans carte d’erreur ni commandes ; Haut trois fois ramène la 59, en direct. Gauche ouvre alors la liste sur cette chaîne, loin sous le haut de la liste ; Droite montre la première catégorie, depuis son haut, sur sa première chaîne ; Gauche revient à toutes les chaînes, sur la chaîne regardée ; Bas depuis la soixantième tourne la page de la liste, Haut la retourne ; OK sur une chaîne la montre, la liste restant sous la télécommande et les commandes ne revenant pas par-dessus ; la touche Lecture/Pause montre elle aussi la chaîne sous la télécommande ; Menu referme la liste et laisse l’image nue, comme elle était. OK rappelle alors les commandes : leur touche Chaînes ouvre la liste à leur place, Menu la referme sur cette touche ; Suivante change de chaîne et garde la télécommande ; Menu quitte enfin la lecture pour le catalogue, sur la chaîne regardée, à la deuxième page, et non sur celle qu’il avait gardée en mémoire.
- **Message**, avec une chaîne que le catalogue de démonstration ne peut pas montrer : au-dessus de la liste des chaînes, le message prend la télécommande, Haut ne la lui retire pas, OK le referme et la liste la retrouve sur la même chaîne ; au-dessus du catalogue, Menu le referme et la chaîne la retrouve. Une chaîne ouverte depuis le catalogue montre ensuite son image nue sous son bandeau ; Bas y change de chaîne aussitôt, et OK rappelle les commandes sur Pause.
- **Pages d’un grand catalogue**, sur 58 093 films aux titres et aux catégories d’un vrai abonnement : les jaquettes commencent sous une seule ligne de commandes ; Haut mène à la recherche, Droite à Page suivante — Page précédente n’a encore rien à montrer —, qui tourne deux pages en gardant la télécommande ; Gauche mène à Page précédente, qui la garde aussi ; Bas entre dans la page par sa première rangée.
- **Pays** : de la liste à la colonne, ouverture des pays sur celui en cours, passage de la France à l’Espagne, réouverture, annulation par Menu, puis Menu qui revient aussitôt à l’accueil et sortie de l’application.
- **Fiche d’un film** : OK sur une jaquette ouvre le panneau de verre sur sa commande de lecture ; les bouts de la rangée de commandes retiennent la télécommande, Bas ne sort pas vers le dock ni vers le catalogue, Haut atteint la croix ; Favoris ouvre les listes sur la première, Menu les referme sans rien enregistrer, puis le choix d’une liste et Enregistrer marquent le titre, la télécommande revenant chaque fois sur Favoris ; Description complète s’ouvre et Menu en revient ; Menu referme la fiche et rend le focus à la jaquette.
- **Fiche d’une série** : depuis la commande de lecture, Gauche entre dans les épisodes sur l’épisode 15 sélectionné et non sur la ligne la plus proche ; Gauche encore entre dans les saisons sur la saison 12 sans rien changer ; Haut passe à la saison 11, dont les épisodes remplacent aussitôt la liste ; Droite mène à son premier épisode puis aux commandes ; Menu revient au rayon, sur la saison 11.
- **Chaîne restaurée** : la chaîne mémorisée perd puis retrouve le focus.
- **Source en erreur** : le bouton de reconnexion suit la télécommande.

Ces parcours ont fait apparaître quatre défauts corrigés avant le portage du lecteur : depuis la première icône du dock, Gauche partait dans la liste au lieu du bouton Retour ; la sonde de mesure du banc, placée entre un bouton et son focus, empêchait d’entrer dans la liste des pays ; à l’ouverture d’une fiche depuis le catalogue, le focus restait sur la jaquette devenue inactive, le panneau encore invisible ne pouvant pas le prendre ; et Menu ne refermait pas les listes d’un titre.

Les parcours du lecteur et de Menu en ont montré cinq autres, tous corrigés. **Pendant un flux, les réglages ne répondaient plus au bout de trois secondes** : les commandes se masquaient sous eux, et la zone invisible qui les rappelle reprenait la télécommande, dont les flèches changeaient alors de chaîne derrière les panneaux. **Un réglage n’était appliqué que par un bouton Enregistrer**, et fermer le panneau le perdait. Depuis la liste des pages, Droite n’entrait dans une page que si un contrôle se trouvait à la hauteur de la ligne. De même, Regarder et Favoris, à côté de l’aperçu d’une chaîne, n’étaient atteints depuis la liste que par hasard d’alignement, et l’image de l’aperçu prenait le focus sans le montrer. Enfin, **en ouvrant une section depuis l’accueil, le dock était dessiné sélectionné alors que la télécommande se trouvait sur le bouton Pays**.

Les deux parcours du zapping et du message, écrits ensuite, en ont montré six de plus, que les captures ne pouvaient pas montrer puisqu’elles ne jouent rien. **Ouverte par la touche Chaînes, la liste se posait sur les commandes** : le bandeau du haut et la barre restaient dessous, la touche Chaînes à moitié couverte ; la liste prend maintenant leur place, sur Mac comme sur Apple TV, et Menu les ramène sur cette touche. **Après un changement de catégorie, la liste restait vide à l’écran** : elle gardait le défilement de la précédente, plus longue, et la télécommande tombait sur un bouton de son en-tête ; une catégorie est maintenant une liste neuve, depuis son haut, et les boutons de l’en-tête ne sont plus que des signes sur Apple TV. **La liste ne dépassait pas les soixante chaînes qu’elle construit autour de la chaîne regardée** : Haut et Bas s’arrêtaient à leurs bouts ; ils tournent maintenant la page. Dans une liste reconstruite sous la télécommande, le système posait le focus sur la première ligne venue et y ramenait le défilement, si bien que la ligne voulue n’était jamais construite : la demande est tenue jusqu’à ce que la ligne dise elle-même qu’elle a la télécommande. **Suivante et Précédente perdaient la télécommande à chaque changement de chaîne**, qui la renvoyait sur Pause : une seconde pression mettait en pause. Enfin **le bouton OK d’un message ne prenait pas la télécommande** : ce qu’un message recouvre est seulement mis hors d’atteinte, le focus y restait, et seul Menu le refermait ; le message la demande maintenant, et la lecture la retrouve ensuite sur sa liste, ses commandes ou l’image.

Une photo du téléviseur a ensuite montré le bandeau d’une chaîne tel qu’il était avant la refonte du lecteur : un nom coupé à six lettres, un numéro replié sur deux lignes, et au même moment le titre en haut, la carte d’ouverture au milieu et la barre en bas. Le bandeau de la refonte ne se repliait plus, mais restait petit — et l’on ne le voyait presque jamais : **changer de chaîne par Haut ou Bas faisait revenir toutes les commandes**, sur Pause, et la pression suivante déplaçait la sélection au lieu de zapper ; il fallait attendre cinq secondes entre deux chaînes. Une chaîne s’ouvre maintenant sur son image nue, sous un bandeau large au pied de l’écran — numéro sur une ligne quel que soit son nombre de chiffres, nom sur toute la ligne, catégorie, heure, rappel des touches —, et Haut et Bas zappent sous ce seul bandeau, qui dit aussi l’ouverture du flux ou son échec à la place de la carte du milieu. Dans la liste des chaînes, les noms étaient coupés avant ce qui les distingue, un numéro ou une marque de qualité : la liste est plus large et un nom rétrécit avant d’être coupé.

Une seconde photo du téléviseur montrait l’écran des films de la 0.8.9, dont les jaquettes ne commencent qu’au milieu de l’écran. Elle a fait regarder celui de la 0.9.0 avec un catalogue de cette taille, ce qu’aucun banc ne faisait : trois films ne demandent pas de pages. **Avec 58 093 films, le nom de l’écran, la recherche et les pages occupaient trois lignes**, et les jaquettes ne commençaient qu’au tiers de la hauteur. Ils tiennent maintenant sur une ligne, sur Mac comme sur Apple TV : les jaquettes commencent cent cinquante-cinq points plus haut sur un téléviseur, et la liste des chaînes montre une ligne de plus. **Tourner une page renvoyait la télécommande sur la première jaquette** : il fallait remonter et retraverser la ligne pour la page suivante, 969 fois pour un tel catalogue. La touche garde maintenant la sélection, et la page se lit depuis son haut.

La ligne unique a déplacé la liste vers le haut, et deux parcours existants ont alors échoué : la colonne de navigation et la liste ne se font plus face ligne à ligne. **Depuis la première chaîne, Gauche tombait sur le champ « Filtrer les catégories »**, voisin par la hauteur ; le moteur de focus va au contrôle le plus proche, et ce qui se trouvait là n’avait jamais été choisi. La colonne s’ouvre maintenant sur la ligne de ce qui est affiché, et l’on en ressort sur le titre quitté, comme le fait déjà le clavier du Mac. Dans l’écran d’une source à reconnecter, **Bas depuis la recherche sautait le bouton Reconnecter** pour aller au dock : la ligne du haut et les avis répondent désormais chacun comme un tout. Cet avis utilisait aussi les grandes polices du système sur un téléviseur ; il a celles du bureau.

Le nouveau scénario du rayon des saisons a montré deux choses que l’œil ne voyait pas. Ses jaquettes, calculées pour la largeur du catalogue, occupaient 53 % de la hauteur de l’écran : le rayon reprend maintenant celles du catalogue, sept par rangée. Et son défilement, qui touchait le bord de la zone sûre, s’étendait dessous : le moteur de focus plaçait les jaquettes à une marge de l’endroit où elles sont dessinées. Deux points de retrait le gardent dans la zone sûre, et la mesure coïncide avec le dessin.

### Captures Mac comparées

Les captures Mac d’avant et d’après le portage des fiches ont été comparées pixel à pixel, hors bandeau de l’heure : la fiche d’un film, la télévision, les films, les favoris et les réglages sont identiques. Seul change le rayon des saisons, dont la rangée du bas se fond au lieu d’être coupée.

La même comparaison a été refaite après la refonte du lecteur : hors des écrans de lecture, toutes les captures du Mac sont identiques à celles du commit précédent, réglages compris.

Elle l’a été une troisième fois après la reprise de la liste des chaînes et des messages : les trente-quatre captures du Mac sont identiques à celles du commit précédent, à l’heure affichée près, liste de zapping comprise — sur Mac elle prenait déjà seule la place des commandes dans la capture, qui masquait pour cela les commandes ; c’est maintenant le comportement réel.

Et une quatrième après le bandeau d’une chaîne : trente-trois des trente-quatre captures sont identiques à celles du commit précédent, à l’heure affichée près. La trente-quatrième est la liste de zapping, élargie pour les noms longs. Deux captures sont nouvelles : le bandeau d’une chaîne, et le parcours de touches qui change de chaîne sous lui.

### GitHub Actions

Le premier envoi du portage sur Apple TV (`1e609c7`) a échoué sur deux étapes des machines hébergées, qui utilisent tvOS 26.5 et un Mac Intel sous macOS 26. Les deux causes étaient dans les bancs et y sont corrigées. Sous tvOS 26.5 le parcours de la boussole interrogeait l’icône de la recherche, qui porte le même identifiant que le champ : le champ avait bien le focus, comme le montrent la capture et l’arbre d’accessibilité de l’échec. Sur le Mac hébergé, la fenêtre reçoit son premier focus natif après son ouverture ; les deux touches du scénario étaient envoyées avant, et ce premier focus écrasait leur résultat. Le banc attend maintenant ce focus quand la fenêtre est au premier plan.

L’envoi suivant (`d51e0ac`) y a passé le Mac, les dix-sept scénarios et cinq parcours sur six, et a révélé un défaut de l’application que tvOS 27.2 ne montre pas : sous tvOS 26.5, annuler la liste des pays par Menu laissait le focus natif sur le filtre des catégories, voisin, alors que le bouton Pays était dessiné sélectionné. Ce bouton ne revient dans la colonne qu’avec la fermeture de la liste, et le focus lui était demandé trop tôt. Il lui est maintenant donné une fois le bouton revenu, comme après le choix d’un pays.

L’envoi de ce correctif (`9390c8e`) a passé cinq parcours, celui des pays compris, et a été interrompu pendant le sixième : la machine hébergée, plus lente ce jour-là, a mis plus que les dix minutes que le banc accordait aux parcours quand ils étaient quatre. Le banc leur accorde maintenant vingt minutes, et l’étape trente-cinq.

L’envoi de ces durées (`aa528d0`) a tout passé. Celui de la refonte du lecteur (`b837737`) a passé le Mac, les vingt et un scénarios et sept parcours sur huit, et a montré un second défaut du même ordre : sous tvOS 26.5, **quitter un direct par Menu ne rendait pas la télécommande à la chaîne dans le catalogue**. La liste revient à l’écran avec la sortie du lecteur, et le focus était demandé à sa ligne avant qu’elle n’existe. La sortie d’un direct passe maintenant par le chemin qui ouvre une section : le catalogue attend la ligne du titre qu’il a en mémoire, et ce titre devient la chaîne regardée, y compris quand elle a été atteinte en zappant. Le retour du rayon d’une série vers son catalogue, écrit de la même façon, suit le même chemin. Les parcours du zapping et du message ont été ajoutés avec ce correctif : ils jouent ces retours, la liste de zapping que le banc n’avait jamais ouverte à la télécommande, et l’ouverture d’une chaîne depuis le catalogue. L’exécution hébergée de leur commit (`5e660c4`) a tout passé, les vingt et un scénarios et les dix parcours sous tvOS 26.5 compris. Celle du bandeau d’une chaîne et du zapping sans commandes (`4c822c9`) a tout passé aussi, vingt-trois scénarios et dix parcours. La ligne unique au-dessus du catalogue et le parcours des pages, ajoutés ensuite, n’ont encore tourné que sous tvOS 27.2 ; l’exécution hébergée de leur commit est leur premier passage sous tvOS 26.5.

### Essai réel

L’application signée localement a été lancée sur le Mac avec la source Xtream déjà enregistrée, sans saisie d’identifiants, puis pilotée par des clics en arrière-plan. **Cet essai a porté sur un état antérieur au dock en bas, à la boussole, aux réglages en verre du lecteur et au portage sur Apple TV.**

- l’application s’ouvre sur l’accueil, qui affiche les 24 665 chaînes de la source ;
- un clic sur TV ouvre la télévision sur la catégorie et la chaîne laissées à la session précédente ;
- un clic sur la chaîne sélectionnée l’ouvre et l’image du direct s’affiche ; au retour, l’aperçu de la chaîne démarre dans le grand cadre ;
- le filtre par langue trouve l’anglais, l’espagnol, le français et l’italien dans 58 110 films, et 9 989 titres sans étiquette ; « Français » retient 14 190 films ;
- la fiche d’un film et la fiche d’une série affichent les jaquettes, les repères, le synopsis et les crédits du fournisseur ;
- Réglages › Sources présente la source avec ses effectifs.

## Non vérifié

- **Apple TV physique** : rien de cette interface n’a été affiché sur un téléviseur ni piloté par une vraie télécommande. Le simulateur ne dit rien de la fluidité, du verre sur une Apple TV HD, ni de la lecture.
- **Liste de zapping** : parcourue à la télécommande sur une lecture simulée — ouverture, catégories, pages, changement de chaîne — jamais sur un direct, où changer de chaîne ouvre un flux. Sur Mac, elle n’est que capturée : ni le clavier ni le pointeur ne l’ont parcourue ; son retrait deux secondes après que le pointeur l’a quittée et sa fermeture d’un clic à côté n’ont pas été vus.
- **Bandeau d’une chaîne sur un vrai flux** : il est exercé sur une lecture simulée, qui s’ouvre en quatre dixièmes de seconde, et sur une chaîne morte simulée. Sa tenue pendant une ouverture longue, les relances d’un vrai moteur avant l’échec et sa lisibilité sur une image claire n’ont pas été vues.
- **Lecteur sur un vrai flux** : les commandes, les langues et les réglages sont exercés sur une lecture simulée, pas sur une vidéo. Le choix d’une piste audio ou d’un sous-titre **par VLC** est écrit d’après l’interface de VLCKit et compile ; il n’a été essayé sur aucun flux. « Relancer le flux » non plus. L’image jusqu’aux bords du téléviseur n’a pas été vue sur un téléviseur.
- **Clavier réel du Mac** : Tab entre les zones, et Échap dans la fenêtre. Les scénarios du banc passent par le traitement des touches, pas par le clavier.
- **Animations** : l’accueil qui se replie vers le dock, le changement de décor sous le pointeur, le boîtier entre le rayon et la fiche. Seuls leurs états de départ et d’arrivée sont capturés.
- **Pointeur réel** : l’agrandissement du dock pendant le mouvement, le glissement d’une icône et la sélection d’une chaîne au simple survol.
- **iPhone et iPad** : compilation seulement.
- **Lecture** au-delà d’une chaîne et d’un aperçu : pas d’essai de film, d’épisode, de reprise ni de réseau dégradé.
- **Ajout ou modification d’une source** : le formulaire est affiché, la saisie et l’envoi ne sont pas exercés.
- **Installateur Mac**.

## Limites connues

- Sur Mac, les pages des Réglages se parcourent au pointeur : les flèches ne les traversent pas. Sur Apple TV, la télécommande les atteint.
- Sur Apple TV, rien ne défile sous la télécommande dans une fiche : le synopsis montre les lignes qui tiennent, le reste se lit dans Description complète.
- Le panneau des listes d’un titre garde sur Mac ses boutons du système ; sur Apple TV il a les tailles et les surbrillances du bureau.
- Le champ de recherche qui a le focus de la télécommande est dessiné clair par le système, dans son cadre de verre.
- Sur Mac, depuis une liste, Retour demande deux pressions pour changer d’écran, la première montrant la boussole ; Réglages › Interface supprime cette étape. Sur Apple TV il n’y a pas de boussole.
- Retour retrace les écrans, pas les catégories parcourues dans un écran : une pression quitte la section, qui se rouvrira sur la catégorie et le titre laissés.
- Pendant la lecture, Favori ajoute ou retire le titre des favoris d’une pression ; le choix parmi plusieurs listes reste dans la fiche et dans le catalogue.
- Les réglages que le moteur lit à l’ouverture d’un flux ne changent pas le flux en cours sans « Relancer le flux ».
- La recherche porte sur la section en cours, pas sur les trois catalogues.
- Le dock ne se réordonne pas à la télécommande.
- Les informations de la chaîne sélectionnée se limitent à ce que fournit la liste ; aucun programme n’est affiché tant que l’EPG n’existe pas.
- La langue d’un pays plurilingue est celle que le système tient pour la plus probable : une étiquette `BE` donne le néerlandais, `CH` l’allemand.
