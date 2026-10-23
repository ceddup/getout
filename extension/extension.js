'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const vscode = require('vscode');
const { normalizeTypes, shouldOpenExternally, bypassKey } = require('./lib');

const DEDUPE_MS = 1000; // same file handed over twice within this delay: ignore
const BYPASS_TTL_MS = 5000; // single-use exemption of "Open in VS Code (text)"
const LOOP_WINDOW_MS = 10000; // hand-over loop guard: window...
const LOOP_MAX = 3; // ...and number of hand-overs after which we stop

const MESSAGES = {
  en: {
    loop: 'getout: the default Windows application for "{ext}" files seems to be VS Code, so "{name}" stays in VS Code. Pick another default application, or remove "{ext}" from getout.externalTypes.',
    failed: 'getout could not open "{name}" with Windows ({error}). It is reopened in VS Code.',
  },
  fr: {
    loop: 'getout : l\u2019application Windows par d\u00e9faut des fichiers "{ext}" semble \u00eatre VS Code, "{name}" reste donc dans VS Code. Choisissez une autre application par d\u00e9faut, ou retirez "{ext}" de getout.externalTypes.',
    failed: 'getout n\u2019a pas pu ouvrir "{name}" avec Windows ({error}). Le fichier est rouvert dans VS Code.',
  },
};

function say(id, vars) {
  const lang = String(vscode.env.language || 'en').toLowerCase().startsWith('fr') ? 'fr' : 'en';
  return MESSAGES[lang][id].replace(/\{(\w+)\}/g, (_, k) => vars[k]);
}

function readTypes() {
  return normalizeTypes(vscode.workspace.getConfiguration('getout').get('externalTypes'));
}

/** Local file URI of a text or custom-editor tab, else undefined. */
function fileUri(tab) {
  const input = tab.input;
  if (!(input instanceof vscode.TabInputText || input instanceof vscode.TabInputCustom)) return undefined;
  return input.uri.scheme === 'file' ? input.uri : undefined;
}

/** True while some open tab, in any group, shows this path. */
function hasTab(key) {
  return vscode.window.tabGroups.all.some((group) =>
    group.tabs.some((tab) => {
      const uri = fileUri(tab);
      return uri !== undefined && bypassKey(uri.fsPath) === key;
    }),
  );
}

function activate(context) {
  let types = readTypes();
  const bypass = new Set(); // paths the user asked to edit as text (single use)
  const textTabs = new Set(); // paths kept in VS Code until their last tab closes
  const handovers = new Map(); // key -> times of recent hand-overs
  const evaluated = new WeakMap(); // tab -> key already judged for that tab

  /** Open a file in VS Code without interception. */
  async function openAsText(uri) {
    const key = bypassKey(uri.fsPath);
    bypass.add(key);
    setTimeout(() => bypass.delete(key), BYPASS_TTL_MS).unref(); // never leave a stale exemption
    await vscode.commands.executeCommand('vscode.openWith', uri, 'default');
  }

  context.subscriptions.push(
    vscode.commands.registerCommand('getout.openAsText', async (arg) => {
      const active = vscode.window.tabGroups.activeTabGroup.activeTab;
      const uri = arg instanceof vscode.Uri ? arg : active && fileUri(active);
      if (uri && uri.scheme === 'file') await openAsText(uri);
    }),
  );

  if (process.platform !== 'win32') return;

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('getout.externalTypes')) types = readTypes();
    }),
  );

  // Tabs already open (restored session) are left alone.
  for (const group of vscode.window.tabGroups.all) {
    for (const tab of group.tabs) {
      const uri = fileUri(tab);
      if (uri) textTabs.add(bypassKey(uri.fsPath));
    }
  }

  function launch(uri) {
    const explorer = path.join(process.env.SystemRoot || 'C:\\Windows', 'explorer.exe');
    const fail = (err) => {
      vscode.window.showErrorMessage(say('failed', { name: path.basename(uri.fsPath), error: err.message || err }));
      openAsText(uri).catch(() => {});
    };
    try {
      const child = spawn(explorer, [uri.fsPath], { detached: true, stdio: 'ignore', windowsHide: false });
      child.on('error', fail);
      child.unref();
    } catch (err) {
      fail(err);
    }
  }

  async function handOver(tab, uri, key) {
    let closed = false;
    try {
      closed = await vscode.window.tabGroups.close(tab);
    } catch (_) {
      // treated like a refused close
    }
    if (closed) {
      launch(uri);
    } else if (hasTab(key)) {
      textTabs.add(key); // the tab stays (e.g. save dialog cancelled): leave it alone
    }
  }

  function check(tab) {
    const uri = fileUri(tab);
    if (!uri) return;
    const fsPath = uri.fsPath;
    const key = bypassKey(fsPath);
    if (evaluated.get(tab) === key || textTabs.has(key)) return;
    if (tab.isDirty) { // being edited here: never take it away
      textTabs.add(key);
      return;
    }
    const wasBypassed = bypass.has(key);
    if (!shouldOpenExternally(fsPath, types, bypass)) {
      evaluated.set(tab, key);
      if (wasBypassed) textTabs.add(key);
      return;
    }
    // Skipped without being judged (file missing, duplicate event): a later `changed` retries.
    if (!fs.existsSync(fsPath)) return;

    const now = Date.now();
    const recent = (handovers.get(key) || []).filter((time) => now - time < LOOP_WINDOW_MS);
    handovers.set(key, recent);
    if (recent.length && now - recent[recent.length - 1] < DEDUPE_MS) return;
    evaluated.set(tab, key);
    if (recent.length >= LOOP_MAX) { // Windows sends the file straight back to VS Code
      textTabs.add(key);
      vscode.window.showWarningMessage(
        say('loop', { name: path.win32.basename(fsPath), ext: path.win32.extname(fsPath).toLowerCase() }),
      );
      return;
    }
    recent.push(now);
    handOver(tab, uri, key).catch(() => {});
  }

  context.subscriptions.push(
    vscode.window.tabGroups.onDidChangeTabs((e) => {
      for (const tab of e.closed) {
        const uri = fileUri(tab);
        if (!uri) continue;
        const key = bypassKey(uri.fsPath);
        if (!hasTab(key)) textTabs.delete(key); // keep it while another tab shows the file
      }
      // `changed` covers a preview tab reused for another file.
      for (const tab of [...e.opened, ...e.changed]) check(tab);
    }),
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
