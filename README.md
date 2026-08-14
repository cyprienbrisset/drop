# Drop

**No account. No cloud. No tracking.**

Drop est un coffre de documents local pour macOS. Vous déposez vos fichiers sur une icône de la barre de menus ; Drop les rend immédiatement cherchables en langage naturel, comprend leur contenu (type, émetteur, montants, dates, échéances) et vous les retrouve en quelques mots — tout cela sans jamais quitter votre Mac.

Parcours en trois temps : **DROP** → **UNDERSTAND** → **FIND**.

## Pourquoi Drop

- **Aucun compte, aucun cloud.** Le coffre vit entièrement sur votre disque, chiffré au repos (AES-256-GCM via SQLCipher, clé Mode Standard générée et gardée dans le Keychain de la machine).
- **Aucun tracking.** Pas de télémétrie, pas d'appel réseau pour fonctionner — la classification, l'OCR et la recherche sémantique tournent sur l'intelligence embarquée d'Apple (Vision, Natural Language, Apple Intelligence quand disponible), jamais via une API tierce.
- **Recherche naturelle.** Une barre de recherche façon Spotlight (⌥ Espace, n'importe où sur le Mac) comprenant montants, dates, émetteurs et types de documents (« facture edf juillet », « contrat > 500€ »...).
- **Compréhension automatique.** Extraction de texte natif + OCR de repli, détection d'entités déterministe (IBAN, SIRET/SIREN, TVA, montants, dates) et classification/résumé par modèle de langage sur l'appareil, sans jamais réécrire un champ que vous avez corrigé vous-même.
- **Coffre robuste.** Déduplication par contenu, vérification d'intégrité périodique, reconstruction de dernier recours depuis les fichiers seuls si l'index est corrompu, corbeille avec rétention avant purge définitive.

## Fonctionnalités

- Dépôt par glisser-déposer sur l'icône de la barre de menus, avec zone de dépôt et retour visuel en temps réel.
- Recherche plein texte + sémantique (lexicale, trigrammes pour la tolérance aux fautes, embeddings pour le sens) avec filtres sur montant, date et type.
- Extraction native pour PDF, texte brut, RTF/RTFD, HTML, DOCX, XLSX, PPTX et images (avec OCR automatique sur les pages scannées ou peu denses en texte).
- Détection d'entités : IBAN, SIRET/SIREN, TVA intracommunautaire, montants, dates, emails, téléphones, organisations connues.
- Correction manuelle des champs (type, émetteur, date effective) avec verrouillage permanent contre toute réécriture automatique ultérieure.
- Tags libres, partagés entre documents.
- Export unitaire ou massif vers un dossier, avec reprise sur interruption.
- Corbeille avec délai de rétention avant purge, restauration en un clic.
- Détection d'échéances explicites (« date limite », « échéance le »...) et rappel local optionnel, jamais programmé sans consentement explicite.
- Import assisté d'un coffre Drop existant (fusion sans doublon, par déduplication de contenu).
- Suivi du budget disque : taille du coffre, économie de déduplication, taille de l'index et des vecteurs.

## Confidentialité et sécurité

- Coffre chiffré au repos avec SQLCipher (AES-256), clé générée et gardée exclusivement dans le Keychain de la machine — jamais sur disque en clair, jamais transmise.
- Aucune donnée ne quitte la machine : pas de compte, pas de synchronisation, pas d'appel réseau pour les fonctions cœur du produit.
- Verrou mono-instance : deux lancements de Drop ne peuvent jamais accéder au même coffre en parallèle.
- Vérification d'intégrité périodique des blobs et reconstruction de l'index depuis les fichiers seuls en dernier recours, sans jamais perdre l'accès aux documents.

## Architecture

Drop est un paquet Swift Package Manager multi-module (Swift 6, concurrence stricte), ciblant macOS 26+ :

```
DropCore          socle : types, erreurs, horloge/FS injectables, notifications, Keychain
DropVault         coffre chiffré sur disque (blobs, déduplication, chiffrement par blob)
DropIndex         index.db (SQLite/SQLCipher via GRDB), migrations, schéma
DropExtraction    extraction de texte (PDF, OOXML, images, OCR Vision)
DropEntities      extraction déterministe d'entités (montants, dates, IBAN, SIRET...)
DropIntelligence  classification/résumé via modèle de langage sur l'appareil
DropEmbeddings    embeddings sémantiques + recherche vectorielle (sqlite-vec)
DropSearch        analyse de requête en langage naturel
DropJobs          file de travaux persistante (analyse en tâche de fond)
DropLicense       vérification de licence, plafond version gratuite
DropFeatures      cas d'usage métier (ingestion, recherche, corrections, import, rappels...)
DropApp           application AppKit/SwiftUI : icône de barre de menus, recherche, préférences
```

## Développement

```bash
git clone git@github.com:<votre-compte>/drop.git
cd drop
./Scripts/link-sqlcipher-framework.sh   # à relancer après tout nettoyage de .build
swift build
swift test
```

L'exécutable `DropApp` est une application menu-bar sans icône Dock (`NSApp.setActivationPolicy(.accessory)`). Aucune fenêtre ne s'ouvre au lancement ; toute l'interface vit dans l'icône de la barre de menus, la fenêtre de recherche et les préférences.

## Licence

Projet en développement actif. Licence à préciser.
