# Feuille de route FLUX IPTV

## Correctif 0.3.1

- Accès optionnel au contrôleur audio VLC et réapplication des réglages à la première lecture. Validation Xcode à refaire.

## Candidat 0.3.0
- [x] Cœur IPTV M3U/Xtream, cache des secrets en mémoire, favoris séparés et listes personnalisées.
- [x] Catalogue partagé SwiftUI TV/Films/Séries, grandes cartes, focus et style glossy.
- [x] AVPlayer + plan de secours VLCKit, adaptateurs vidéo Mac/UIKit, URL épisodes et fallback, messages sans identifiants.
- [x] Pavé tactile virtuel de première génération, clavier, bridge GameController Mac/iOS, focus natif tvOS.
- [x] Cibles Xcode macOS, iOS, tvOS générées à partir des mêmes fichiers.
- [x] Tests Foundation (23) + analyse syntaxique, vérification des références des projets.
- [ ] Résolution SPM et compilation Xcode des trois cibles, sans signature en CI ; signature stable pour essai réel.
- [ ] Validation sur Mac : TV HLS/TS, VOD MP4/MKV, épisodes, bascule moteurs, plein écran, Trousseau, anciennes listes, fluidité de très gros catalogues.
- [ ] Validation tvOS simulateur puis Apple TV physique (Siri Remote 1re génération : swipe, press, long press, MENU, play/pause, zapping/seek), focus des modales, mémoire et rendu.
- [ ] Vérification iPhone/iPad (rotation, taille de grille, clavier, saisie Xtream, lecture).

## Prochaines étapes
- [ ] EPG/XMLTV, programme actuel/suivant, historique/reprise, lecture automatique épisodes, choix audio et sous-titres pour les deux moteurs.
- [ ] Cache d'affiches et catalogues borné, index de recherche, catégories et navigation rapides sur gros catalogues.
- [ ] Transfert sécurisé de la configuration entre appareils avec accord de l'utilisateur ; jamais de secrets en clair.
- [ ] Vérification licences VLC et dépendances, icônes/App Store, réduction des exceptions ATS, politiques confidentialité et tests appareils.

Ne jamais fournir de contenu ou de comptes, ni journaliser d'identifiants.
