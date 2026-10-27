'use strict';

// Pins the tab semantics of extension.js with stubbed `vscode` and `child_process`.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');

const EXTENSION = require.resolve('../extension/extension');
const tick = () => new Promise((resolve) => setImmediate(resolve));

class TabInputText { constructor(uri) { this.uri = uri; } }
class TabInputCustom { constructor(uri) { this.uri = uri; } }
class Uri { constructor(fsPath) { this.scheme = 'file'; this.fsPath = fsPath; } }

/** Loads a fresh extension against a fake VS Code; returns helpers to drive it. */
function setup({ closeResult = true, spawnMode = 'ok', legacyUp = false, revealFails = false } = {}) {
  const log = { spawned: [], warnings: [], errors: [], executed: [], closed: [], revealed: [] };
  const state = { closeResult, spawnMode, legacyUp, revealFails };
  const groups = [{ tabs: [] }, { tabs: [] }];
  const listeners = [];
  const commands = {};
  let clock = 1000000;

  const fire = (e) => listeners.forEach((l) => l({ opened: [], closed: [], changed: [], ...e }));
  const tabGroups = {
    all: groups,
    activeTabGroup: { activeTab: undefined },
    onDidChangeTabs: (l) => { listeners.push(l); return { dispose() {} }; },
    close: async (tab) => {
      log.closed.push(tab.input ? tab.input.uri.fsPath : tab.label);
      if (!state.closeResult) return false;
      for (const g of groups) g.tabs = g.tabs.filter((t) => t !== tab);
      fire({ closed: [tab] });
      return true;
    },
  };
  const vscode = {
    Uri, TabInputText, TabInputCustom,
    env: { language: 'en' },
    window: {
      tabGroups,
      showWarningMessage: (m) => log.warnings.push(m),
      showErrorMessage: (m) => log.errors.push(m),
    },
    workspace: {
      getConfiguration: () => ({ get: () => undefined }), // default types
      onDidChangeConfiguration: () => ({ dispose() {} }),
    },
    commands: {
      registerCommand: (name, fn) => { commands[name] = fn; return { dispose() {} }; },
      executeCommand: async (...args) => {
        log.executed.push(args[0]);
        if (args[0] !== 'revealFileInOS') return;
        log.revealed.push(args[1].fsPath);
        if (state.revealFails) throw new Error('reveal failed');
      },
    },
  };
  const childProcess = {
    spawn: (cmd, args) => {
      log.spawned.push([cmd, ...args]);
      if (state.spawnMode === 'throw') throw new Error('spawn threw');
      return {
        on(event, fn) {
          if (event === 'error' && state.spawnMode === 'error') setImmediate(() => fn(new Error('spawn failed')));
        },
        unref() {},
      };
    },
  };

  const net = {
    connect: () => {
      const handlers = {};
      const socket = { setTimeout() {}, once(event, fn) { handlers[event] = fn; return socket; }, destroy() {} };
      setImmediate(() => (state.legacyUp ? handlers.connect() : handlers.error(new Error('ECONNREFUSED'))));
      return socket;
    },
  };

  const originalLoad = Module._load;
  const originalNow = Date.now;
  Module._load = function (request, ...rest) {
    if (request === 'vscode') return vscode;
    if (request === 'child_process') return childProcess;
    if (request === 'net') return net;
    return originalLoad.call(this, request, ...rest);
  };
  Date.now = () => clock;
  delete require.cache[EXTENSION];
  const extension = require(EXTENSION);
  extension.activate({ subscriptions: [] });

  return {
    log, vscode, groups, state,
    advance: (ms) => { clock += ms; },
    open(file, { group = 0, dirty = false } = {}) {
      const tab = { input: new TabInputText(new Uri(file)), isDirty: dirty };
      groups[group].tabs.push(tab);
      fire({ opened: [tab] });
      return tab;
    },
    /** A tab of VS Code's integrated browser: no input type in the API, only a label. */
    browse(label) {
      const tab = { input: undefined, label, isDirty: false };
      groups[0].tabs.push(tab);
      fire({ opened: [tab] });
      return tab;
    },
    change: (tab) => fire({ changed: [tab] }),
    fire,
    commands,
    teardown() {
      Module._load = originalLoad;
      Date.now = originalNow;
      delete require.cache[EXTENSION];
    },
  };
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'getout-test-'));
const file = (name) => {
  const p = path.join(dir, name);
  fs.writeFileSync(p, 'x');
  return p;
};
test.after(() => fs.rmSync(dir, { recursive: true, force: true }));

const opts = { skip: process.platform !== 'win32' && 'interception is Windows only' };

test('opened listed tab: close then hand over to explorer', opts, async () => {
  const env = setup();
  try {
    const md = file('a.md');
    env.open(md);
    await tick();
    assert.deepEqual(env.log.closed, [md]);
    assert.equal(env.log.spawned.length, 1);
    assert.equal(path.basename(env.log.spawned[0][0]).toLowerCase(), 'explorer.exe');
    assert.equal(env.log.spawned[0][1], md);
  } finally { env.teardown(); }
});

test('unlisted and missing files are left alone', opts, async () => {
  const env = setup();
  try {
    env.open(file('a.txt'));
    env.open(path.join(dir, 'missing.md'));
    await tick();
    assert.equal(env.log.spawned.length, 0);
    assert.equal(env.log.closed.length, 0);
  } finally { env.teardown(); }
});

test('changed on the same tab with the same key does nothing more', opts, async () => {
  const env = setup();
  try {
    const tab = env.open(file('b.md'));
    await tick();
    env.advance(5000);
    env.change(tab);
    env.change(tab);
    await tick();
    assert.equal(env.log.spawned.length, 1);
  } finally { env.teardown(); }
});

test('preview tab reused for another listed file is handed over', opts, async () => {
  const env = setup();
  try {
    const other = file('c2.md');
    const tab = { input: new TabInputText(new Uri(file('c1.txt'))), isDirty: false };
    env.groups[0].tabs.push(tab);
    env.fire({ opened: [tab] });
    tab.input = new TabInputText(new Uri(other));
    env.change(tab);
    await tick();
    assert.deepEqual(env.log.closed, [other]);
    assert.equal(env.log.spawned.length, 1);
  } finally { env.teardown(); }
});

test('open as text: no interception, and later changes keep the tab', opts, async () => {
  const env = setup();
  try {
    const md = file('d.md');
    await env.commands['getout.openAsText'](new Uri(md));
    const tab = env.open(md);
    env.change(tab);
    env.advance(5000);
    env.change(tab);
    await tick();
    assert.deepEqual(env.log.executed, ['vscode.openWith']);
    assert.equal(env.log.closed.length, 0);
    assert.equal(env.log.spawned.length, 0);
  } finally { env.teardown(); }
});

test('moved text tab (open new, close old, same key) stays exempt', opts, async () => {
  const env = setup();
  try {
    const md = file('e.md');
    await env.commands['getout.openAsText'](new Uri(md));
    const oldTab = env.open(md, { group: 0 });
    // drag to the other group: new tab opens, old one closes
    const newTab = env.open(md, { group: 1 });
    env.groups[0].tabs = [];
    env.fire({ closed: [oldTab] });
    env.advance(5000);
    env.change(newTab);
    await tick();
    assert.equal(env.log.closed.length, 0);
    assert.equal(env.log.spawned.length, 0);
    // once the last tab closes, the exemption ends
    env.groups[1].tabs = [];
    env.fire({ closed: [newTab] });
    env.open(md);
    await tick();
    assert.equal(env.log.spawned.length, 1);
  } finally { env.teardown(); }
});

test('dirty tab is never closed', opts, async () => {
  const env = setup();
  try {
    const tab = env.open(file('f.md'), { dirty: true });
    tab.isDirty = false;
    env.change(tab); // saved: still not taken away
    await tick();
    assert.equal(env.log.closed.length, 0);
    assert.equal(env.log.spawned.length, 0);
  } finally { env.teardown(); }
});

test('close resolving false: no spawn, tab left alone afterwards', opts, async () => {
  const env = setup({ closeResult: false });
  try {
    const tab = env.open(file('g.md'));
    await tick();
    assert.equal(env.log.closed.length, 1);
    assert.equal(env.log.spawned.length, 0);
    env.advance(5000);
    env.change(new Proxy(tab, {})); // another object for the same tab
    await tick();
    assert.equal(env.log.closed.length, 1);
  } finally { env.teardown(); }
});

test('loop guard: after 3 hand-overs the file stays in VS Code with a warning', opts, async () => {
  const env = setup();
  try {
    const md = file('h.md');
    for (let i = 0; i < 3; i += 1) {
      env.open(md);
      await tick();
      env.advance(1500); // Windows sends the file back to VS Code
    }
    assert.equal(env.log.spawned.length, 3);
    const tab = env.open(md);
    await tick();
    assert.equal(env.log.spawned.length, 3);
    assert.equal(env.log.warnings.length, 1);
    assert.match(env.log.warnings[0], /default Windows application/);
    assert.ok(env.groups[0].tabs.includes(tab));
    env.open(md); // exempt until the tabs close
    await tick();
    assert.equal(env.log.spawned.length, 3);
  } finally { env.teardown(); }
});

test('a tab skipped by the 1 s dedupe is handed over on a later change', opts, async () => {
  const env = setup();
  try {
    const md = file('j.md');
    env.open(md);
    await tick();
    const second = env.open(md); // same file again within 1 s: skipped, tab stays
    await tick();
    assert.equal(env.log.spawned.length, 1);
    assert.ok(env.groups[0].tabs.includes(second));
    env.advance(2000);
    env.change(second);
    await tick();
    assert.equal(env.log.spawned.length, 2);
    assert.equal(env.groups[0].tabs.includes(second), false);
  } finally { env.teardown(); }
});

test('a tab opened before its file exists is handed over once it does', opts, async () => {
  const env = setup();
  try {
    const md = path.join(dir, 'late.md');
    const tab = env.open(md);
    await tick();
    assert.equal(env.log.spawned.length, 0);
    fs.writeFileSync(md, 'x');
    env.change(tab);
    await tick();
    assert.equal(env.log.spawned.length, 1);
  } finally { env.teardown(); }
});

for (const spawnMode of ['error', 'throw']) {
  test(`spawn failure (${spawnMode}): error shown, file reopened as text, no loop`, opts, async () => {
    const env = setup({ spawnMode });
    try {
      const md = file(`k-${spawnMode}.md`);
      env.open(md);
      await tick();
      await tick();
      assert.equal(env.log.errors.length, 1);
      assert.match(env.log.errors[0], /could not open/);
      assert.deepEqual(env.log.executed, ['vscode.openWith']);
      const reopened = env.open(md); // what openWith does: bypass key is consumed
      env.advance(5000);
      env.change(reopened);
      await tick();
      assert.equal(env.log.spawned.length, 1);
      assert.equal(env.log.closed.length, 1);
    } finally { env.teardown(); }
  });
}

test('blocked binary: tab closed, file shown in File Explorer, never run', opts, async () => {
  const env = setup();
  try {
    const exe = file('setup.exe');
    env.open(exe);
    await tick();
    assert.deepEqual(env.log.closed, [exe]);
    assert.deepEqual(env.log.revealed, [exe]);
    assert.equal(env.log.spawned.length, 0);
  } finally { env.teardown(); }
});

test('blocked text types (scripts) stay in VS Code', opts, async () => {
  const env = setup();
  try {
    env.open(file('run.ps1'));
    env.open(file('app.js'));
    env.open(file('tool.py'));
    await tick();
    assert.equal(env.log.closed.length, 0);
    assert.equal(env.log.executed.length, 0);
    assert.equal(env.log.spawned.length, 0);
  } finally { env.teardown(); }
});

test('open as text on a blocked binary keeps it in VS Code', opts, async () => {
  const env = setup();
  try {
    const exe = file('tool.exe');
    await env.commands['getout.openAsText'](new Uri(exe));
    const tab = env.open(exe);
    env.advance(5000);
    env.change(tab);
    await tick();
    assert.deepEqual(env.log.executed, ['vscode.openWith']);
    assert.equal(env.log.closed.length, 0);
  } finally { env.teardown(); }
});

test('repeated clicks on a binary never raise the loop warning', opts, async () => {
  const env = setup();
  try {
    const exe = file('again.exe');
    for (let i = 0; i < 4; i += 1) {
      env.open(exe);
      await tick();
      env.advance(1500);
    }
    assert.equal(env.log.revealed.length, 4);
    assert.equal(env.log.warnings.length, 0);
  } finally { env.teardown(); }
});

test('reveal failure: error shown, file reopened in VS Code', opts, async () => {
  const env = setup({ revealFails: true });
  try {
    const exe = file('broken.exe');
    env.open(exe);
    await tick();
    await tick();
    assert.equal(env.log.errors.length, 1);
    assert.match(env.log.errors[0], /could not open/);
    assert.deepEqual(env.log.executed, ['revealFileInOS', 'vscode.openWith']);
    const reopened = env.open(exe); // what openWith does: bypass key is consumed
    env.advance(5000);
    env.change(reopened);
    await tick();
    assert.equal(env.log.revealed.length, 1);
  } finally { env.teardown(); }
});

test('diff tabs are never intercepted', opts, async () => {
  const env = setup();
  try {
    const md = file('i.md');
    env.fire({ opened: [{ input: { original: new Uri(md), modified: new Uri(md) }, isDirty: false }] });
    await tick();
    assert.equal(env.log.spawned.length, 0);
  } finally { env.teardown(); }
});

test('getout 1 link in the integrated browser: tab closed, error shown once', opts, async () => {
  const env = setup();
  try {
    const tab = env.browse('localhost:8765');
    await tick();
    await tick();
    assert.deepEqual(env.log.closed, ['localhost:8765']);
    assert.equal(env.log.errors.length, 1);
    assert.match(env.log.errors[0], /getout 1 format/);
    env.change(tab);
    await tick();
    await tick();
    assert.equal(env.log.errors.length, 1);
    assert.equal(env.log.spawned.length, 0);
  } finally { env.teardown(); }
});

test('browser tab whose label becomes the getout 1 address is handled', opts, async () => {
  const env = setup();
  try {
    const tab = env.browse('Browser');
    await tick();
    assert.equal(env.log.closed.length, 0);
    tab.label = '127.0.0.1:8765';
    env.change(tab);
    await tick();
    await tick();
    assert.deepEqual(env.log.closed, ['127.0.0.1:8765']);
    assert.equal(env.log.errors.length, 1);
  } finally { env.teardown(); }
});

test('getout 1 address still served, or other browser tabs: left alone', opts, async () => {
  const env = setup({ legacyUp: true });
  try {
    env.browse('localhost:8765');
    env.browse('localhost:3000');
    await tick();
    await tick();
    assert.equal(env.log.closed.length, 0);
    assert.equal(env.log.errors.length, 0);
  } finally { env.teardown(); }
});
