[English](AGENT-INSTALL.md)

# Installer getout (instructions pour un agent IA)

getout est une extension VS Code : un clic sur un chemin de fichier local dans le chat ouvre le fichier dans son application Windows. L'installeur installe l'extension et ajoute une règle aux instructions globales des agents. Windows uniquement.

## 1. Demande à l'utilisateur (saute ce qu'il a déjà dit)

- **Langue** : `en` ou `fr`. Elle fixe la langue des messages et de la règle.
- **Agents qui reçoivent la règle** : toi-même par défaut. N'ajoute un autre agent (Claude Code `claude`, Codex `codex`, Gemini CLI `gemini`) que si l'utilisateur le confirme. `none` n'écrit aucune règle.

Prérequis : VS Code avec sa ligne de commande `code`. Si une ancienne version à serveur local de getout est installée, l'installeur refuse : demande à l'utilisateur de lancer d'abord sa désinstallation.

## 2. Lance l'installeur

Lance la commande depuis PowerShell ou bash (dans cmd.exe, les apostrophes ne protègent rien). Remplace `fr` et `claude` par les réponses (plusieurs agents : `-Agents claude,codex`).

```
powershell -NoProfile -ExecutionPolicy Bypass -Command '$ErrorActionPreference=[Management.Automation.ActionPreference]::Stop; & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1))) -Yes -Lang fr -Agents claude; exit $LASTEXITCODE'
```

Code de sortie 0 : c'est installé. Sinon, montre la sortie à l'utilisateur et arrête-toi : ne réessaie pas à l'aveugle. Si l'installeur ne trouve pas VS Code, demande à l'utilisateur le chemin de `code.cmd` et ajoute `-CodeCli <chemin>`, protégé selon ton shell (un chemin avec des espaces est délicat à protéger dans la commande entre apostrophes : dans le doute, fais lancer l'installeur par l'utilisateur dans son propre PowerShell).

## 3. Si ton agent n'est pas géré

Pour un agent autre que `claude`, `codex` ou `gemini` : installe avec `-Agents none`, puis ajoute toi-même la règle à ton fichier d'instructions globales. Récupère https://raw.githubusercontent.com/ceddup/getout/main/rules/rule.fr.md (`rule.en.md` pour l'anglais) et colle son contenu entre ces deux lignes, en les gardant telles quelles (elles délimitent le bloc pour qu'on puisse le retirer à la main). Le désinstalleur ne retire pas le bloc d'un agent non géré : dis-le à l'utilisateur, pour qu'il le supprime lui-même à la désinstallation :

```
<!-- getout:begin -->
<!-- getout:end -->
```

## 4. Vérifie

Dis à l'utilisateur de redémarrer VS Code (ou de lancer « Développeur : Recharger la fenêtre »), puis de cliquer, dans une nouvelle conversation, sur un lien vers un fichier `.drawio` ou `.md` : il doit s'ouvrir dans son application Windows, pas dans un onglet VS Code. Si l'application Windows par défaut de ce type est VS Code lui-même, getout avertit et garde le fichier dans VS Code.

Pour désinstaller : https://github.com/ceddup/getout/blob/main/README.fr.md#désinstallation
