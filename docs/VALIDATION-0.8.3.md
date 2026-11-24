# Validation FLUX IPTV 0.8.3 — Correctif de compilation

Correctif du 24 novembre 2026, à partir de la version 0.8.2 (`f051f17c9f7312a2582f59fbafeb6ebd9861a870`). La capture Xcode fournie par l’utilisateur montre trois erreurs `Main actor-isolated property player cannot be referenced from a nonisolated context` et un avertissement d’API obsolète.

## Cause et correction

Les trois erreurs se trouvent dans le `deinit` de `CaseMediaPreviewController`. Le destructeur non isolé lisait la propriété enveloppée `@Published player`, isolée sur MainActor. Les callbacks du lecteur étaient déjà renvoyés sur MainActor.

Le nettoyage du lecteur est désormais une action `@MainActor @Sendable`, qui capture uniquement le lecteur et son jeton d’observation. L’arrêt explicite retire cette action puis l’exécute immédiatement sur MainActor. Le destructeur peut copier cette action Sendable et la planifier sur MainActor, sans lire `player`, sans capturer le contrôleur détruit et sans supposer sur quel exécuteur sa dernière référence est libérée. Retrait de l’observateur périodique, pause et retrait de l’item sont conservés.

Dans `PlaybackController`, `mediaSelectionGroup(forMediaCharacteristic:)` est remplacé par `loadMediaSelectionGroup(for:)`. Les groupes sont chargés une fois par item natif et publiés sur MainActor. Changement d’item ou arrêt annule le chargement et vide les groupes. Une réponse ou une option liée à un ancien item ne peut pas modifier le lecteur courant.

La version visible passe à 0.8.3, build 16. L’installateur utilise un répertoire de compilation `DerivedData-083`. Les fonds 0.8.2 restent identiques et vérifiables par leur manifeste.

## Vérifications ciblées

Un programme minimal reproduit exactement les trois erreurs avec Swift 6.2, en modes de langage 5 et 6. Le pattern corrigé compile sans diagnostic dans ces deux modes, avec `-strict-concurrency=complete -warnings-as-errors`.

Un test de cycle de vie vérifie : arrêt explicite une seule fois ; dernière référence libérée dans `Task.detached` avec nettoyage exécuté sur MainActor ; redémarrage avec un nettoyage par lecteur. Un test des méthodes de sélection des pistes vérifie : réponse tardive ignorée, ancienne option refusée, option courante acceptée et arrêt/annulation sans publication tardive.

**Ces tests ciblés utilisent des substituts pour AVFoundation et le wrapper Published. Ils vérifient les règles Swift d’isolation et la logique de cycle de vie, pas les types réels du SDK Apple.** Les traces se trouvent dans `validation/actor-fix-0.8.3.txt`.

## Contrôles du projet

- 98 tests du cœur Swift : réussis, zéro échec.
- Garde SwiftSyntax : 68 fichiers contrôlés, aucune déclaration attribuée invalide.
- Analyse syntaxique : 45 fichiers partagés, succès pour macOS 14, iOS 17 et tvOS 17.
- Projet Xcode régénéré : trois cibles, version 0.8.3, build 16.
- Syntaxe des scripts shell et format des plist : valides.
- Les 18 images HD passent le vérificateur de dimensions, intégrité et empreintes.

Le journal du cœur de cette version se trouve dans `validation/core-tests-0.8.3.txt`. Le rapport 0.8.2 est conservé à titre historique.

## Limite de validation

Aucun SDK Apple n’est disponible dans l’environnement local. Les précédentes tâches GitHub Actions ont échoué avant l’affectation d’un runner. **La compilation Xcode complète, la lecture AVPlayer et la navigation sur appareil Apple restent à confirmer.** Il ne faut pas confondre analyse syntaxique, tests avec substituts et compilation native.

## Essai sur le Mac

Fermer le projet 0.8.2, décompresser l’archive 0.8.3 et ouvrir le projet Xcode de ce nouveau dossier, puis choisir FluxIPTV / My Mac et lancer. L’installateur Mac fourni compile également cette version. Vérifier l’ouverture et la fermeture d’un aperçu, le changement rapide de boîte et la sélection des pistes après un changement de vidéo.
