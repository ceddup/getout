[Français](AGENT-INSTALL.fr.md)

# Installing getout (instructions for an AI agent)

getout is a VS Code extension: a click on a local file path in the chat opens the file in its Windows application. The installer installs the extension and adds a rule to the agents' global instructions. Windows only.

## 1. Ask the user (skip what they already said)

- **Language**: `en` or `fr`. It sets the language of the messages and of the rule.
- **Agents that get the rule**: yourself by default. Add another agent (Claude Code `claude`, Codex `codex`, Gemini CLI `gemini`) only if the user confirms. `none` writes no rule.

Prerequisite: VS Code with its `code` command line. If an earlier localhost version of getout is installed, the installer refuses: ask the user to run its uninstall first.

## 2. Run the installer

Run it from PowerShell or bash (in cmd.exe, single quotes do not quote). Replace `en` and `claude` with the answers (several agents: `-Agents claude,codex`).

```
powershell -NoProfile -ExecutionPolicy Bypass -Command '$ErrorActionPreference=[Management.Automation.ActionPreference]::Stop; & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ceddup/getout/main/install.ps1))) -Yes -Lang en -Agents claude; exit $LASTEXITCODE'
```

Exit code 0 means installed. Otherwise show the output to the user and stop: do not retry blindly. If the installer does not find VS Code, ask the user for the path of `code.cmd` and add `-CodeCli <path>`, quoted for your shell (a path with spaces is tricky inside the single-quoted command: if in doubt, have the user run the installer from their own PowerShell).

## 3. If your agent is not supported

For an agent other than `claude`, `codex` or `gemini`: install with `-Agents none`, then add the rule yourself to your global instructions file. Fetch https://raw.githubusercontent.com/ceddup/getout/main/rules/rule.en.md (`rule.fr.md` for French) and paste its content between these two lines, keeping them exactly (they delimit the block so it can be removed by hand). The uninstaller does not remove the block for an unsupported agent: tell the user, so they know to delete it themselves when uninstalling.

```
<!-- getout:begin -->
<!-- getout:end -->
```

## 4. Verify

Tell the user to restart VS Code (or run "Developer: Reload Window"), then to click a link to a `.drawio` or `.md` file in a new chat: it must open in its Windows application, not in a VS Code tab. If the default Windows application for that type is VS Code itself, getout warns and keeps the file in VS Code.

To uninstall: https://github.com/ceddup/getout#uninstall
