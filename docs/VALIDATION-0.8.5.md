# FLUX IPTV 0.8.5 — Lecteur, verre et bandes-annonces

Version du 25 novembre 2026, build 18, issue de la base 0.8.4 `ba80c313df30e35c9913526c12147f30394297ee`.

## Problèmes corrigés

Le bandeau du catalogue restait affiché pendant la lecture en mode fenêtre. La barre de transport occupait toute la largeur et une seconde couche de transport pouvait apparaître dans le lecteur. La vue de lecture retire maintenant la navigation générale, garde la vidéo à sa taille lorsque les commandes apparaissent, et affiche des panneaux flottants de largeur bornée. Ils s’effacent après trois secondes d’inactivité, sauf pendant une pause, un chargement, une erreur, une interaction ou l’usage de VoiceOver.

Les commandes vidéo utilisent `glassEffect(.clear)` et `GlassEffectContainer` avec les SDK et systèmes 26 compatibles. Les versions antérieures utilisent le matériau système translucide. Réduire la transparence et Réduire les animations conservent leur priorité.

La chaîne Apple utilise désormais macOS 26 et Xcode 26.3, avec une vérification bloquante des trois SDK. Le précédent Xcode 16.4 sélectionné par défaut sur le runner macOS 15 compilait entièrement hors du binaire la branche Liquid Glass. Un lancement sur un système récent ne pouvait pas rétablir ce code absent.

Les liens YouTube étaient tous classés comme pages externes. Une route dédiée valide maintenant les identifiants et utilise le lecteur officiel dans une `WKWebView` sur macOS/iOS. Les URL natives conservent AVPlayer. Un champ fournisseur vide ou `0` ne masque plus un autre champ de bande-annonce valide.

Le lecteur reste le même entre miniature et plein écran ; le retour rétablit la sourdine. Une surface WebKit réelle suit la projection de la boîte. La conversion des coordonnées Y se calibre sur la caméra du renderer. Le cadre de sélection utilise un trait fin qui n’occulte plus le synopsis.

L’ouverture directe de la bande-annonce en plein écran conserve la demande de son pendant le fondu initial : le premier relevé de sourdine du lecteur, encore en préparation, ne remplace plus cette demande.

## Vérifications automatisées

Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) associe ses résultats au commit exact :

- Tests Swift du cœur, dont routes YouTube, données fournisseur, homographie, dimensions et visibilité du cadre.
- Vérification des déclarations d’état, du projet Xcode régénéré et des 18 fonds embarqués.
- Compilation Xcode distincte pour macOS, iOS Simulator et tvOS Simulator.
- Sur macOS, `scripts/test-youtube-session.sh` charge le vrai document du lecteur dans une vraie WKWebView, avec une API IFrame locale contrôlée. Il vérifie la traversée JavaScript/Swift, la différence entre prêt et en lecture, la sourdine, les commandes, les erreurs, le déplacement de la même vue entre hôtes SwiftUI et sa libération.
- Archives des applications après compilation réussie, journaux et pack de sources du commit avec SHA-256.

Le test WebKit remplace seulement le fournisseur réseau par une fixture. **Il ne prouve pas la lecture réelle d’une vidéo YouTube ni celle du fournisseur IPTV.** Une compilation ne prouve pas non plus le rendu perceptuel de Liquid Glass, la fluidité sur chaque appareil ou les gestes physiques de télécommande. Les journaux de l’exécution du commit restent l’autorité sur le succès ou l’échec de chaque vérification.

## Comportements délibérés et limites

- L’image du film est privilégiée lorsqu’AVFoundation peut l’extraire. Une image du fournisseur ou une miniature de bande-annonce identifiée comme telle sert de secours. L’absence d’image ne bloque plus une bande-annonce disponible.
- Le délai d’aperçu reste réglable à 3, 5 ou 10 secondes. Le cadre passe progressivement vers le lecteur prêt ; la lecture YouTube attend que la transition de visibilité soit terminée.
- Un petit cadre YouTube propose **Agrandir pour lire la bande-annonce**. L’autoplay intégré exige un cadre d’au moins 200 × 200 points et une surface visible supérieure à la moitié.
- Une vidéo absente des métadonnées n’est pas inventée. Les refus d’intégration, les vidéos retirées et les erreurs de réseau ont un état explicite et une action de reprise ou d’ouverture externe.
- tvOS ne propose pas de vue web. Les bandes-annonces vidéo directes y restent intégrées ; YouTube s’ouvre explicitement sur iPhone par QR code.
- Les builds Mac ne sont pas notariés pour distribution ; les builds iOS/tvOS des Actions ciblent les simulateurs. Le projet complet permet de signer sur les appareils de l’utilisateur.

## Références d’implémentation

- [Apple : Liquid Glass dans les vues personnalisées](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple : variante Clear](https://developer.apple.com/documentation/swiftui/glass/clear)
- [Apple : disponibilité des vues web](https://developer.apple.com/design/human-interface-guidelines/web-views)
- [YouTube : identité de l’application, visibilité et taille du lecteur](https://developers.google.com/youtube/terms/required-minimum-functionality)
- [YouTube : IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)
- [GitHub : image macOS 26 et versions de Xcode](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
