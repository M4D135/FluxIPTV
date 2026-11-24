# Feuille de route : Flux IPTV

## V0.1, MVP macOS

- [x] SwiftUI + fenêtre native macOS
- [x] Playlist M3U URL et import local
- [x] Connexion Xtream / catalogue Live + VOD
- [x] Lecture AVPlayer, recherche, catégories, favoris
- [x] Stockage des secrets dans le Trousseau
- [x] Swift Package Core et tests unitaires de parsing
- [ ] Validation d'une compilation réelle sur macOS/Xcode
- [ ] Essais d'intégration avec des sources de test autorisées

## V0.2, qualité de lecture

- [ ] Support fiable des flux TS/MKV/codec audio non natif (analyse d'un backend libmpv / VLC sous licence compatible)
- [ ] Indicateur de qualité, buffer et erreurs réseau explicites
- [ ] Reconnexion auto, reprise du direct, parcours télécommande simulé
- [ ] Mise en cache limitée des catalogues et chargement incrémental pour grosses listes
- [ ] Édition des sources et choix du format HLS/TS après création
- [ ] Amélioration des contrôles de sécurité sur les domaines HTTP

## V0.3, catalogue enrichi

- [ ] Séries Xtream : saisons / épisodes
- [ ] EPG XMLTV + Xtream `get_short_epg`, programme en cours
- [ ] Historique et reprise de lecture VOD, options audio / sous-titres
- [ ] Import M3U étendu (groupes imbriqués, headers spécifiques, autres encodages)

## V1.0, port tvOS

- [ ] Ajouter une cible `FluxIPTVTV` en gardant exactement le même `FluxIPTVCore`
- [ ] Interface spécifique **focus engine tvOS** et télécommande Siri Remote
- [ ] Ajouter une source via saisie simplifiée ou appairage depuis Mac/iPhone
- [ ] Lecture AVPlayer plein écran, navigation rapide des chaînes
- [ ] Favoris/sources partageables via synchronisation sécurisée facultative
- [ ] Bench mémoire/CPU sur vraie Apple TV, HLS et sous-titres

## Principes de développement

- Le code réseau et les parseurs ne dépendent pas de SwiftUI / AppKit.
- Aucun contenu, compte ou fournisseur IPTV n'est intégré.
- Ne jamais exposer d'identifiants dans les logs, les captures CI ou Git.
- Tester sur un vrai Mac avant de qualifier une release.
