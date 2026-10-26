[Français](README.fr.md)

# getout

Click a file path in your AI agent's chat in VS Code, it opens in its Windows app.

A `.drawio` opens in draw.io, a `.md` in your default Markdown app, a `.docx` in Word, a `.xlsx` in Excel. No browser tab, no local server.

## Install

Requirements: Windows 10/11, VS Code with its `code` command line, Windows PowerShell 5.1 (included in Windows).

**Option A: let your agent do it.** Paste this into your agent's chat:

> Install getout for me: read https://raw.githubusercontent.com/ceddup/getout/main/AGENT-INSTALL.md and follow it.

**Option B: one command**, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1 | iex
```

With parameters:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1))) -Lang en -Agents claude
```

| Parameter | Meaning |
| --- | --- |
| `-Lang en\|fr` | Language of the messages and of the agent rule (default: the language of the previous install, else the Windows display language). |
| `-Agents` | Agents that get the rule: a list among `claude`, `codex`, `gemini`, or `none`. Default: those of the previous install, else asked in an interactive session, else none. |
| `-Yes` | Never ask. |
| `-Ref` | Branch or tag to install from (default `main`). |
| `-CodeCli` | Path of `code.cmd`, if the installer does not find VS Code. |

Then **restart VS Code** (or run "Developer: Reload Window"). Agents pick up the rule in their next session.

If you installed the earlier localhost version, run its uninstall first (the installer refuses otherwise), from PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\getout\uninstall.ps1"`.

## What it does

- **The extension.** When VS Code opens a tab on a local file of a listed type, getout closes the tab and hands the file to Windows (`explorer.exe <path>`), which opens it in the associated application. It works for a link clicked in a chat, `Ctrl+P`, the explorer.
- **The list.** Setting `getout.externalTypes`, default: `.md`, `.html`, `.pdf`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.drawio`, `.vsdx`, `.docx`, `.xlsx`, `.pptx`, `.odt`, `.ods`. Edit it in your user settings.
- **Edit in VS Code anyway.** Right-click the file in the explorer or on its tab: **Open in VS Code (text)**.
- **The agent rule.** The installer adds a short block, between `<!-- getout:begin -->` and `<!-- getout:end -->`, to the agent's global instructions (`~\.claude\CLAUDE.md`, `~\.codex\AGENTS.md`, `~\.gemini\GEMINI.md`). It tells the agent to write every file it cites as a plain path link. Running the installer again updates the block in place.
- **Default app is VS Code?** The file would bounce back. getout notices (3 hand-overs of the same file in 10 seconds), keeps the file in VS Code and shows a warning: pick another default app for that type, or remove it from the list.
- **Launch failure?** An error message is shown and the file is reopened in VS Code.

## Security

- Executables, scripts, interpreters, macro-enabled Office files and disk images (`.exe`, `.bat`, `.ps1`, `.js`, `.docm`, `.xlsm`, `.iso`...) are on a fixed blocklist: never handed to Windows, even if you list them. Legacy `.doc`, `.xls` and `.ppt` can carry macros and are not blocked: add them knowingly.
- The setting is application-scoped: a workspace's `.vscode/settings.json` cannot change it.
- Diff tabs are never intercepted. A tab with unsaved changes, and tabs already open when VS Code starts, are left alone.
- Nothing listens on the network. The only thing getout runs is `explorer.exe` on a file you opened.
- Disabled in Restricted Mode (untrusted workspace).
- The installer downloads its sources from this repository. It installs the extension through the VS Code command line, edits only the agent instruction files (between the markers above), and keeps a small state file, `%LOCALAPPDATA%\getout\state.json`.

## Limits

- The tab appears for a split second before it closes.
- Interception applies to every opening inside VS Code (`Ctrl+P`, explorer), not only to links in a chat: hence the right-click **Open in VS Code (text)**.
- VS Code only (and forks that accept the VSIX). In a terminal, a path stays a path.
- Windows only.
- The Claude Code VS Code extension's own tool-call rows (the files it reads or edits) still open in the editor.
- Restart VS Code (or reload the window) after installing.
- Agent sessions already open keep their former instructions until you start a new one. Coming from getout 1, their links (`http://localhost:8765/...`) no longer work: getout closes the browser tab such a link opens and says so in a notification.

## Uninstall

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1))) -Uninstall
```

From a clone of this repository: `powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1`. It removes the extension, the rule blocks and the state file.

## Development

```powershell
node --test
powershell -NoProfile -ExecutionPolicy Bypass -File test\install.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File test\install.smoke.ps1
```

The smoke test needs the VS Code command line and skips itself without it. It only touches temporary folders.

## License

[MIT](LICENSE)
