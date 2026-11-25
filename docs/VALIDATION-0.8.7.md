# FLUX IPTV 0.8.7 — Rayons de saisons et projet Apple TV

Version du 25 novembre 2026, build 20, issue de la livraison 0.8.6 `b4e9b4c7f800cb804c11d764d3d1752e392aa7ec`.

## Modifications

Le boîtier tenu occupe presque toute la zone disponible. Sa pose est ajustée localement : la caméra et le rayon de voisins restent fixes pendant une rotation ou l’ouverture d’une saison. Les voisins sont placés derrière l’enveloppe de rotation du boîtier, avec une marge de profondeur. L’aperçu reste attaché à la face effectivement rendue.

Choisir une série ouvre son rayon de saisons. Les saisons fournies, y compris les spéciaux, restent accessibles sans la fenêtre de huit tranches de l’ancien pack. Choisir une saison ouvre la présentation existante des épisodes. Reposer revient aux saisons ; Retour depuis ce rayon retrouve le catalogue des séries. Le retour depuis la lecture retrouve la saison et la page de l’épisode quitté. Les retours au pointeur recentrent la jaquette correspondante.

Le Dock affiche ses actions avec icônes et libellés, sans menu de compactage. La recherche dispose d’une grande capsule loupe à côté de TV, Films et Séries. Le verso conserve uniquement le synopsis IPTV : les fournisseurs de descriptions Wikipédia/Allociné, les sélecteurs et leurs liens sont retirés.

Le décodage des épisodes valide séparément les extensions de premier niveau et imbriquées. Une valeur vide, nulle ou invalide ne masque plus une extension valide dans `info`. Les erreurs AVPlayer sont classées sans recopier des URL authentifiées ou des messages arbitraires. Sur Mac, l’ouverture volontaire dans VLC permet de choisir parmi les adresses validées lorsque plusieurs existent. AVPlayer reste le seul moteur intégré au Mac.

Les deux appels nécessaires à la compatibilité avec l’ancien Trousseau macOS sont isolés dans un pont C, avec suppression locale de leur avertissement de dépréciation. Leur comportement est conservé : désactivation temporaire de l’interaction, opération synchrone, restauration exacte de l’état précédent même en cas d’erreur. Aucune migration d’entrée, modification de service ou désactivation globale des avertissements n’est effectuée.

`FluxIPTV-AppleTV.xcodeproj` contient uniquement la cible tvOS et le schéma partagé `FluxIPTVTV`. Il référence exactement les mêmes sources et ressources que la cible Apple TV du projet multiplateforme. Le lanceur et `LISEZ-MOI APPLE TV.txt` expliquent la sélection du schéma, la destination et la signature sur appareil.

## Vérifications à lire dans l’exécution du commit

Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) fournit les résultats pour chaque commit. Cette liste décrit les contrôles exécutés ; seul le statut des jobs de cette exécution établit leur réussite.

- Tests Swift du cœur, dont extensions d’épisodes, variantes de lecture, diagnostics sans secrets, cadrage des boîtiers et navigation existante.
- Contrôle des déclarations SwiftUI et régénération déterministe des deux projets Xcode.
- Intégrité des 18 fonds 3840 × 2160. Les ressources de la 0.8.6 restent inchangées.
- Compilation macOS universelle, iOS Simulator, tvOS Simulator et tvOS ARM64 pour appareil avec Xcode 26.3.
- Pont C compilé avec `-Wall -Wextra -Werror`, et garde Swift avec avertissements traités comme erreurs. Vérification de l’état d’interaction, des appels imbriqués, des exceptions et de la restauration. Aucun élément de Trousseau n’est lu, écrit ou supprimé par ce test.
- Vraie WKWebView avec fournisseur IFrame local : état, commandes, pause/reprise, session unique et libération.
- Vrai AVPlayer avec vidéo locale : délai TV, sélection, annulation, sourdine, repli d’adresse et libération.
- Vrai renderer SceneKit : tailles et positions projetées des voisins, caméra fixe, séparation de profondeur, dimensions du boîtier et projection de l’aperçu, y compris pendant une animation.
- Quatre captures natives avec données locales : TV, films, rayon de 12 saisons et saison 12 ouverte sur l’épisode 15 avec son Dock. Elles permettent d’examiner l’en-tête, les espacements et les matières.
- Archives d’applications et sources provenant du commit exécuté, avec identifiant du commit et empreintes SHA-256.

## Limites

Ces contrôles utilisent des données et des vidéos locales. Ils ne démontrent pas la lecture de l’épisode précis montré dans la capture de l’utilisateur, ni l’accès à son fournisseur. L’erreur AVPlayer −11828 indique un format non reconnu ; elle ne suffit pas à prouver que le serveur renvoie du MKV, qu’une extension est erronée ou que les identifiants sont refusés. La correction d’extension couvre un défaut indépendant effectivement présent dans le code.

La compilation tvOS pour appareil ne remplace pas un essai sur une Apple TV physique. Un compte et une signature de l’utilisateur restent nécessaires à l’installation. Le paquet tvOS Simulator ne s’installe pas sur une vraie Apple TV. Les builds Mac de CI ne sont pas notariés.

Les bandes-annonces YouTube restent intégrées sur Mac/iOS et proposées par QR code sur tvOS. Les vidéos directes restent intégrées selon leurs formats. Les fonds 4K sont précalculés ; aucun runtime FERRO n’est ajouté. La fluidité et les gestes d’une télécommande physique restent à vérifier sur le matériel de l’utilisateur.

Références Apple : [sélection du schéma et de la destination](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), [trousseaux macOS — TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains), [format non reconnu](https://developer.apple.com/documentation/avfoundation/averror-swift.struct/code/fileformatnotrecognized).
