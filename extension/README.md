# getout

Open linked files in their default Windows application instead of a VS Code tab.

When VS Code opens a tab on a local file of a listed type (a link clicked in an AI
assistant's chat, `Ctrl+P`, the explorer), getout closes the tab and hands the file to
Windows (`explorer.exe <path>`), which opens it in the associated application: draw.io for
`.drawio`, your browser for `.md`, Word, Excel, and so on.

## Settings

`getout.externalTypes`: list of extensions to hand to Windows. Default:
`.md`, `.html`, `.pdf`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.drawio`, `.vsdx`,
`.docx`, `.xlsx`, `.pptx`, `.odt`, `.ods`.

Executable, script and macro-enabled types (`.exe`, `.bat`, `.ps1`, `.js`, `.docm`, ...) are
never handed to Windows, even when listed. Those VS Code cannot display (`.exe`, `.msi`,
`.msix`, `.lnk`, `.iso`, ...) close their tab and are shown selected in File Explorer, never run.

The setting is application-scoped: a workspace `.vscode/settings.json` cannot change it.

If the default Windows application for a type is VS Code itself, the file would bounce
back and forth. getout detects it (3 hand-overs of the same file within 10 seconds), keeps
the file in VS Code and shows a warning: pick another default application or remove the
type from the list.

## Edit a file in VS Code anyway

Right-click the file in the explorer or its tab and choose **Open in VS Code (text)**.

## Limitations

- The tab appears for a fraction of a second, then closes.
- Interception applies to every opening inside VS Code (`Ctrl+P`, explorer), hence the
  right-click command.
- Windows only. Diff tabs and files already open when VS Code starts are left alone.
- Works in VS Code and derivatives that accept the VSIX; in a terminal, a path stays a path.
- Links of getout 1 (`http://localhost:8765/...`), written by agent sessions started before
  the upgrade, no longer work: getout closes the browser tab they open and shows a
  notification. Start a new agent session.

## License

MIT
