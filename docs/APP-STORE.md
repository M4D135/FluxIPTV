# Publier FLUX IPTV sur l’App Store

État au 26 novembre 2026, version 0.9.4. David : « je vais la publier un jour, faut regarder bien les exigences d’Apple sur le code, sécurité, etc. et corriger ».

Ce document liste ce que la revue d’Apple et App Store Connect exigent, ce que la 0.9.4 a corrigé, et ce qui reste à faire au moment de publier. Une première relecture a été faite par le Spark ; chaque point a ensuite été vérifié dans le code et dans la documentation d’Apple. Trois de ses propositions ont été écartées, car elles auraient cassé l’application ou étaient inexactes (voir « Écarté »).

## Corrigé dans la 0.9.4

| Exigence | Ce qui a été fait |
|---|---|
| **Manifeste de confidentialité** (obligatoire depuis mai 2024, refus ITMS-91053 sinon) | `FluxIPTVMac/PrivacyInfo.xcprivacy`, copié dans les trois applications. Aucun suivi, aucune donnée collectée. Raisons déclarées :<br>• `UserDefaults` : CA92.1, les réglages de l’app ;<br>• `SystemBootTime` : 35F9.1, l’intervalle entre deux appuis de touche ;<br>• `FileTimestamp` : C617.1 et 3B52.1, utilisés par VLCKit sur les fichiers de l’app et ceux choisis par l’utilisateur ;<br>• `DiskSpace` : E174.1, utilisé par VLCKit. |
| **Chiffrement à l’export** | `ITSAppUsesNonExemptEncryption = NO` dans les trois `Info.plist`. L’app n’utilise que le HTTPS du système et le trousseau, qui sont exemptés. App Store Connect ne pose donc plus la question à chaque envoi. |
| **Réseau local** | `NSLocalNetworkUsageDescription` dans les trois `Info.plist`. Un serveur IPTV peut être chez l’utilisateur (box, NAS) : iOS affiche alors cette phrase dans sa demande d’autorisation. |
| **Bandes-annonces YouTube sur Apple TV** (règles 5.2.2 et 5.2.3, conditions d’utilisation de YouTube) | Sur tvOS, YouTubeKit lit le flux d’une vidéo YouTube sans passer par le lecteur officiel. C’est contraire aux conditions de YouTube et c’est un motif de refus connu.<br>La version App Store se génère sans lui : `FLUX_APP_STORE=1 scripts/generate-xcodeproj.py` écrit `FluxIPTV-AppStore.xcodeproj`, qui ne lie pas YouTubeKit et compile avec `FLUX_APP_STORE`. Les bandes-annonces disparaissent alors de l’Apple TV.<br>Sur Mac et iOS, le lecteur YouTube officiel intégré reste autorisé. Les versions installées depuis Xcode gardent tout. |
| **Licences** (LGPL 2.1 de VLCKit, MIT de YouTubeKit) | Réglages › Diagnostic › Licences : nom de chaque composant, licence, adresse de son code source. VLCKit est un framework dynamique séparé, ce que demande la LGPL pour pouvoir le remplacer. Le code de FLUX est public. |
| **Retour à l’accueil de l’Apple TV** (règle de tvOS : Retour à la racine quitte l’app) | La touche Retour n’est pas interceptée à l’accueil de FLUX. Le nouveau comportement de Retour (« Remonter à la barre ») ne s’applique qu’à l’intérieur des écrans. |

## Écarté

- **Ajouter `NSAllowsArbitraryLoadsInWebContent` à ATS.** Dès qu’une de ces clés est présente, iOS et tvOS ignorent `NSAllowsArbitraryLoads` : `NSAllowsArbitraryLoadsForMedia`, `NSAllowsArbitraryLoadsInWebContent`, `NSAllowsLocalNetworking`. Les comptes Xtream en HTTP ne répondraient plus. On garde `NSAllowsArbitraryLoads` seul, avec la justification écrite plus bas.
- **Supprimer les appels au trousseau « fichier » du Mac** (`SecKeychainSetUserInteractionAllowed`). Une API publique dépréciée n’est pas un motif de refus. Ces deux appels lisent sans dialogue les identifiants déjà enregistrés (TN3137 d’Apple). On les garde.
- **Codes de raison inventés** (« CA1.0 », « C6.0 »…). Les codes retenus ci-dessus sont ceux de la documentation d’Apple.

## À faire au moment de publier

1. **Archiver** depuis `FluxIPTV-AppStore.xcodeproj` (`FLUX_APP_STORE=1 scripts/generate-xcodeproj.py`), en configuration Release.
2. **Lire le courriel d’App Store Connect** après le premier envoi. S’il signale `ITMS-91053` pour `Frameworks/VLCKit.framework/VLCKit`, ajouter dans le framework un manifeste avec les mêmes raisons. Il faut alors une phase de script qui le copie puis re-signe le framework. Le manifeste de l’app couvre normalement ces appels, mais Apple n’a jamais dit clairement s’il couvre aussi les frameworks.
3. **Notes pour la revue**, à coller dans App Store Connect :

   > FLUX IPTV is a media player only. It ships no content, no channel list, and no account. Users add their own M3U playlist or Xtream Codes account from their provider. Many providers serve HTTP only, hence NSAllowsArbitraryLoads: the app connects only to the servers the user enters. Credentials stay in the Keychain on the device. To test, add this playlist in Settings › Sources › Add › M3U: (URL of the demo playlist below).

4. **Liste de démonstration pour la revue.** Une M3U qui ne contient que les flux d’essai publiés par Apple, à héberger à une adresse fixe, par exemple dans le dépôt. Ne jamais y mettre de chaîne d’un fournisseur.
5. **Politique de confidentialité.** Une page publique est obligatoire, même sans collecte. Brouillon : [CONFIDENTIALITE.md](CONFIDENTIALITE.md).
6. **Étiquettes de confidentialité** : « Aucune donnée collectée ».
7. **Classification d’âge.** Répondre au questionnaire. Le contenu vient de l’utilisateur et n’est pas filtré : une classification élevée est probable.
8. **Captures** :
   - Apple TV 1920 × 1080 ou 3840 × 2160 ;
   - iPhone 6,9 pouces ;
   - iPad 13 pouces ;
   - Mac 16:10.
   Les bancs en produisent déjà de propres.
9. **Métadonnées.** Ne citer ni chaîne, ni film, ni fournisseur. Ne montrer dans les captures que des titres fictifs, comme ceux des bancs.

## La boutique à venir

- Les thèmes, fonds et packs d’icônes se vendent en **achats intégrés**, par StoreKit 2 (règle 3.1.1). Aucun paiement extérieur, aucun lien vers un site d’achat.
- Chaque collection est un achat **non consommable**.
- **Essayer reste gratuit**, comme dans le studio aujourd’hui.
- Un bouton **« Restaurer les achats »** est obligatoire.
- Les droits sont relus au lancement (`Transaction.currentEntitlements`) puis suivis (`Transaction.updates`).
- Le partage familial est possible.
- Les images vendues restent dans l’app, ou se téléchargent depuis un hébergement d’Apple (fichiers hébergés par l’App Store). Aucun code n’est téléchargé (règle 2.5.2).

## Rappels techniques

- Le Mac est en bac à sable : client réseau, et lecture des fichiers choisis par l’utilisateur.
- Aucune API privée. Ni `dlopen`, ni `NSSelectorFromString`, ni clé `_privée`.
- Ni publicité, ni suivi, ni analytique.
