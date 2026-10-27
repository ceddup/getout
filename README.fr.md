[English](README.md)

# getout

Cliquez sur un chemin de fichier dans le chat de votre agent IA dans VS Code : il s'ouvre dans son application Windows.

Un `.drawio` s'ouvre dans draw.io, un `.md` dans votre application Markdown par défaut, un `.docx` dans Word, un `.xlsx` dans Excel. Pas d'onglet de navigateur, pas de serveur local.

## Installation

Prérequis : Windows 10/11, VS Code avec sa ligne de commande `code`, Windows PowerShell 5.1 (fourni avec Windows).

**Option A : laissez votre agent faire.** Collez ceci dans le chat de votre agent :

> Installe getout pour moi : lis https://raw.githubusercontent.com/ceddup/getout/main/AGENT-INSTALL.fr.md et suis-le.

**Option B : une commande**, dans PowerShell :

```powershell
irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1 | iex
```

Avec paramètres :

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1))) -Lang fr -Agents claude
```

| Paramètre | Rôle |
| --- | --- |
| `-Lang en\|fr` | Langue des messages et de la règle pour les agents (par défaut : la langue de l'installation précédente, sinon la langue d'affichage de Windows). |
| `-Agents` | Agents qui reçoivent la règle : une liste parmi `claude`, `codex`, `gemini`, ou `none`. Par défaut : ceux de l'installation précédente, sinon demandés en session interactive, sinon aucun. |
| `-Yes` | Ne rien demander. |
| `-Ref` | Branche ou étiquette à installer (par défaut `main`). |
| `-CodeCli` | Chemin de `code.cmd`, si l'installeur ne trouve pas VS Code. |

Ensuite, **redémarrez VS Code** (ou lancez « Développeur : Recharger la fenêtre »). Les agents prennent la règle en compte à leur prochaine session.

Si vous avez installé la version précédente, à serveur local, lancez d'abord sa désinstallation (l'installeur refuse sinon), depuis PowerShell : `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\getout\uninstall.ps1"`.

## Ce que ça fait

- **L'extension.** Quand VS Code ouvre un onglet sur un fichier local d'un type de la liste, getout ferme l'onglet et passe le fichier à Windows (`explorer.exe <chemin>`), qui l'ouvre dans l'application associée. Cela vaut pour un lien cliqué dans un chat, `Ctrl+P`, l'explorateur.
- **La liste.** Réglage `getout.externalTypes`, par défaut : `.md`, `.html`, `.pdf`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.drawio`, `.vsdx`, `.docx`, `.xlsx`, `.pptx`, `.odt`, `.ods`. À modifier dans vos paramètres utilisateur.
- **Exécutables.** Un lien vers un exécutable, un installeur, un raccourci ou une image disque (`.exe`, `.msi`, `.msix`, `.lnk`, `.iso`...), que VS Code ne sait pas afficher, ferme son onglet et montre le fichier sélectionné dans l'Explorateur de fichiers. Rien ne s'exécute tant que vous ne double-cliquez pas dessus.
- **Éditer quand même dans VS Code.** Clic droit sur le fichier dans l'explorateur ou sur son onglet : **Ouvrir dans VS Code (texte)** (« Open in VS Code (text) » si VS Code est en anglais).
- **La règle pour les agents.** L'installeur ajoute un court bloc, entre `<!-- getout:begin -->` et `<!-- getout:end -->`, aux instructions globales de l'agent (`~\.claude\CLAUDE.md`, `~\.codex\AGENTS.md`, `~\.gemini\GEMINI.md`). Il demande à l'agent d'écrire tout fichier cité en simple lien de chemin. Relancer l'installeur met le bloc à jour sur place.
- **L'application par défaut est VS Code ?** Le fichier ferait des allers-retours. getout le détecte (3 passages du même fichier en 10 secondes), garde le fichier dans VS Code et affiche un avertissement : choisissez une autre application par défaut pour ce type, ou retirez-le de la liste.
- **Échec du lancement ?** Un message d'erreur s'affiche et le fichier est rouvert dans VS Code.

## Sécurité

- Les exécutables, scripts, interpréteurs, fichiers Office avec macros et images disque (`.exe`, `.bat`, `.ps1`, `.js`, `.docm`, `.xlsm`, `.iso`...) figurent sur une liste noire figée : jamais confiés à Windows, même si vous les ajoutez à la liste. Les anciens `.doc`, `.xls` et `.ppt` peuvent contenir des macros et ne sont pas bloqués : ne les ajoutez qu'en connaissance de cause.
- Le réglage est de portée application : le `.vscode/settings.json` d'un espace de travail ne peut pas le modifier.
- Les onglets de diff ne sont jamais interceptés. Un onglet avec des modifications non enregistrées, et les onglets déjà ouverts au démarrage de VS Code, sont laissés tels quels.
- Rien n'écoute sur le réseau. La seule chose que getout lance est `explorer.exe` sur un fichier que vous avez ouvert, ou « Afficher dans l'Explorateur de fichiers » de VS Code pour un binaire bloqué.
- Désactivé en mode restreint (espace de travail non approuvé).
- L'installeur télécharge ses sources depuis ce dépôt. Il installe l'extension via la ligne de commande de VS Code, ne modifie que les fichiers d'instructions des agents (entre les balises ci-dessus) et garde un petit fichier d'état, `%LOCALAPPDATA%\getout\state.json`.

## Limites

- L'onglet apparaît une fraction de seconde avant de se refermer.
- L'interception vaut pour toute ouverture dans VS Code (`Ctrl+P`, explorateur), pas seulement pour les liens d'un chat : d'où le clic droit **Ouvrir dans VS Code (texte)**.
- VS Code uniquement (et ses dérivés qui acceptent la VSIX). Dans un terminal, un chemin reste un chemin.
- Windows uniquement.
- Les lignes d'outils de l'extension VS Code de Claude Code (les fichiers qu'elle lit ou modifie) ouvrent toujours le fichier dans l'éditeur.
- Redémarrez VS Code (ou rechargez la fenêtre) après l'installation.
- Les sessions d'agent déjà ouvertes gardent leurs anciennes instructions jusqu'à ce que vous en ouvriez une nouvelle. En venant de getout 1, leurs liens (`http://localhost:8765/...`) ne fonctionnent plus : getout ferme l'onglet de navigateur qu'ouvre un tel lien et l'explique dans une notification.

## Désinstallation

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1))) -Uninstall
```

Depuis un clone de ce dépôt : `powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1`. Cela retire l'extension, les blocs de règle et le fichier d'état.

## Développement

```powershell
node --test
powershell -NoProfile -ExecutionPolicy Bypass -File test\install.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File test\install.smoke.ps1
```

Le test de bout en bout a besoin de la ligne de commande de VS Code et s'ignore sans elle. Il ne touche qu'à des dossiers temporaires.

## Licence

[MIT](LICENSE)
