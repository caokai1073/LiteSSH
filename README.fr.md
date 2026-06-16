<div align="center">

<img src="assets/icon.png" width="140" alt="Icône LiteSSH">

# LiteSSH

**Client SSH natif macOS — terminal, explorateur de fichiers et transfert entre serveurs dans une seule fenêtre**

[Télécharger](#télécharger) · [Fonctionnalités](#fonctionnalités) · [Démarrage rapide](#démarrage-rapide) · [Architecture](#architecture) · [Créer un DMG](#créer-un-dmg)

[English](README.md) · [中文](README.zh.md) · [日本語](README.ja.md) · **Français** · [Español](README.es.md) · [한국어](README.ko.md)

</div>

---

## Télécharger

[**→ Télécharger la dernière version**](https://github.com/YOUR_USERNAME/LiteSSH/releases/latest)

Nécessite macOS 13 Ventura ou version ultérieure. Ouvrez le `.dmg` et faites glisser **LiteSSH** dans le dossier Applications.

---

## Fonctionnalités

| | |
|---|---|
| **Terminal complet** | Propulsé par SwiftTerm, ANSI/VT100 complet — htop, nvtop, vim fonctionnent sans configuration |
| **Explorateur de fichiers** | Navigation par drill-in dans la barre latérale, barre d'adresse, répertoire parent, nouveau dossier |
| **Envoi / Téléchargement** | Glissez des fichiers locaux pour les envoyer ; clic droit ou glisser les éléments distants pour les télécharger — **fichiers et dossiers** pris en charge |
| **Transfert entre serveurs** | Cochez plusieurs fichiers/dossiers → clic droit → transférer vers un autre serveur avec progression en temps réel |
| **Authentification PEM / clé privée** | Mot de passe, clé privée et fichiers AWS `.pem` pris en charge. La phrase secrète est fournie automatiquement depuis le Trousseau |
| **Identifiants saisis une seule fois** | Saisissez le mot de passe ou la phrase secrète à l'ajout du serveur ; aucune nouvelle saisie lors des connexions suivantes |
| **Interface bilingue** | La langue de l'interface suit les paramètres système (chinois / anglais) |
| **Mode sombre / clair** | Les couleurs du terminal s'adaptent automatiquement à l'apparence du système |

---

## Démarrage rapide

Il s'agit d'un **Swift Package** pur — aucun `.xcodeproj` nécessaire.

```
1. Ouvrir Package.swift dans Xcode
2. Attendre la résolution des dépendances (SwiftTerm — accès à github.com requis)
3. Sélectionner le schème "LiteSSH" → ▶ Exécuter
4. Cliquer sur "+" pour ajouter un serveur — hôte, port, nom d'utilisateur et identifiants, une seule fois
```

---

## Architecture

LiteSSH n'implémente pas le protocole SSH. Il délègue tout à l'OpenSSH intégré à macOS (`/usr/bin/ssh`, `/usr/bin/sftp`).

**Réutilisation de la connexion.** La première connexion devient le ControlMaster. Toutes les opérations de fichiers suivantes partagent le même socket ControlPath — aucune ré-authentification.

**Sécurité des identifiants.** Les mots de passe et phrases secrètes sont stockés dans le Trousseau macOS. Au moment de l'exécution, `AskPassHelper` fournit un script `SSH_ASKPASS` temporaire afin que le sous-processus ssh/sftp récupère le secret via une variable d'environnement — il n'apparaît jamais dans les arguments du processus.

**Transfert de fichiers.** Utilise `sftp -b <batchfile>` (pas scp) pour éviter les problèmes de parsing des chemins contenant des espaces. Le transfert récursif de répertoires utilise `get -r` / `put -r`. Le transfert entre serveurs transite par un répertoire temporaire local.

**Sécurité des pipes.** Les deux pipes stdout et stderr sont lus en continu via `readabilityHandler` pendant l'exécution du processus, évitant le blocage dû au remplissage du tampon de pipe de 64 Ko.

---

## Structure du projet

```
Sources/LiteSSH/
├── Models/
│   ├── ServerProfile.swift          # Modèle de configuration serveur
│   └── RemoteFile.swift             # Entrée de fichier distant
├── Services/
│   ├── SSHConnection.swift          # Connexion principale + gestion ControlMaster
│   ├── ProcessRunner.swift          # Enveloppe sous-processus (lecture parallèle des pipes)
│   ├── ProfileStore.swift           # Persistance de la configuration
│   ├── KeychainHelper.swift         # Lecture / écriture Trousseau
│   └── AskPassHelper.swift          # Fourniture non-interactive des identifiants SSH_ASKPASS
├── ViewModels/
│   ├── SessionStore.swift           # Correspondance Profile → SSHConnection
│   └── FileBrowserStore.swift       # État de l'explorateur (chemin + pile de retour)
├── Views/
│   ├── Sidebar/
│   │   ├── ServerListView.swift     # Barre latérale : liste serveurs + colonne explorateur
│   │   └── ServerEditView.swift     # Formulaire ajout / modification serveur
│   ├── Terminal/
│   │   ├── TerminalContainerView.swift
│   │   └── TerminalViewRegistry.swift
│   ├── Files/
│   │   └── CrossTransferSheet.swift # Interface de transfert entre serveurs
│   ├── DetailView.swift
│   └── ContentView.swift
├── Localization.swift               # L10n.s(chinois, anglais)
└── LiteSSHApp.swift                 # Point d'entrée @main + AppDelegate
```

---

## Créer un DMG

```bash
cd "SSH tool/LiteSSH"
chmod +x build_dmg.sh
./build_dmg.sh
```

Génère `LiteSSH-1.0.dmg` et `LiteSSH.app` à la racine du projet. Le script compile le binaire en mode release, génère l'icône, signe en ad-hoc et crée le DMG avec un lien symbolique vers Applications. Pour une distribution à d'autres machines, remplacez la signature ad-hoc par un certificat Developer ID.

---

## Dépendances

| Dépendance | Version | Rôle |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | ≥ 1.0 | Émulateur de terminal |
| macOS OpenSSH | Intégré | Protocole SSH / SFTP |
| macOS Keychain | Intégré | Stockage sécurisé des identifiants |

**Configuration requise :** macOS 13 Ventura ou version ultérieure · Xcode 15+ (développement uniquement)

---

## Licence

Apache 2.0
