'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  DEFAULT_TYPES,
  BLOCKED,
  normalizeTypes,
  shouldOpenExternally,
  bypassKey,
  isLegacyLinkLabel,
} = require('../extension/lib');

const TYPES = ['.drawio', '.md'];

test('listed extensions open externally, case-insensitively', () => {
  assert.equal(shouldOpenExternally('C:\\docs\\schema.drawio', TYPES, new Set()), true);
  assert.equal(shouldOpenExternally('C:\\docs\\SCHEMA.DRAWIO', TYPES, new Set()), true);
  assert.equal(shouldOpenExternally('C:\\docs\\readme.md', TYPES, new Set()), true);
});

test('unlisted extensions and extensionless files stay in VS Code', () => {
  assert.equal(shouldOpenExternally('C:\\src\\Program.cs', TYPES, new Set()), false);
  assert.equal(shouldOpenExternally('C:\\src\\notes.txt', TYPES, new Set()), false);
  assert.equal(shouldOpenExternally('C:\\src\\Makefile', TYPES, new Set()), false);
});

test('blocked extensions never open, even when listed', () => {
  assert.equal(shouldOpenExternally('C:\\tmp\\setup.exe', ['.exe', '.md'], new Set()), false);
  assert.equal(shouldOpenExternally('C:\\tmp\\SETUP.EXE', ['.exe'], new Set()), false);
});

test('normalizeTypes lowercases, adds dots, dedupes and drops blocked', () => {
  assert.deepEqual(normalizeTypes(['DRAWIO', '.exe', '.md', '.md']), ['.drawio', '.md']);
});

test('normalizeTypes falls back to defaults on invalid input', () => {
  assert.deepEqual(normalizeTypes('x'), DEFAULT_TYPES);
  assert.deepEqual(normalizeTypes(undefined), DEFAULT_TYPES);
  assert.deepEqual(normalizeTypes(null), DEFAULT_TYPES);
  assert.deepEqual(normalizeTypes([1, 'md']), DEFAULT_TYPES);
});

test('bypass is single-use and removes the key', () => {
  const file = 'C:\\docs\\Schema.drawio';
  const bypass = new Set([bypassKey(file)]);
  assert.equal(shouldOpenExternally(file, TYPES, bypass), false);
  assert.equal(bypass.size, 0);
  assert.equal(shouldOpenExternally(file, TYPES, bypass), true);
});

test('bypass key ignores case and path separator style', () => {
  const bypass = new Set([bypassKey('C:\\Docs\\Schema.drawio')]);
  assert.equal(shouldOpenExternally('c:/docs/schema.DRAWIO', TYPES, bypass), false);
});

test('paths with spaces, accents and apostrophes are handled', () => {
  const p = 'C:\\Users\\Jean Martin\\Documents\\L\u00e9a\'s \u00e9tude\\sch\u00e9ma final.drawio';
  assert.equal(shouldOpenExternally(p, TYPES, new Set()), true);
});

test('no default type is blocked', () => {
  for (const t of DEFAULT_TYPES) {
    assert.equal(BLOCKED.has(t), false, t);
  }
});

test('macro-enabled and script types are blocked even when listed', () => {
  for (const ext of ['.docm', '.xlsm', '.ps1', '.vbs', '.js']) {
    assert.equal(shouldOpenExternally('C:\\tmp\\file' + ext, [ext], new Set()), false, ext);
  }
});

test('interpreters, launchers and macro-capable formats are blocked, plain documents are not', () => {
  const blocked = ['.py', '.pyw', '.pl', '.rb', '.php', '.sh', '.bash', '.ps', '.jnlp', '.wsb', '.rdp',
    '.xlsb', '.xla', '.ppa', '.pps', '.dot', '.xlt', '.iqy', '.slk', '.iso', '.img', '.vhd', '.vhdx'];
  for (const ext of blocked) assert.equal(BLOCKED.has(ext), true, ext);
  for (const ext of ['.doc', '.xls', '.ppt', '.txt', '.csv']) assert.equal(BLOCKED.has(ext), false, ext);
});

test('normalizeTypes drops macro-enabled types', () => {
  assert.deepEqual(normalizeTypes(['.docm', 'XLSM', '.pptm', '.docx']), ['.docx']);
});

test('trailing dots and spaces do not hide the real extension', () => {
  assert.equal(shouldOpenExternally('C:\\tmp\\setup.exe ', ['.exe'], new Set()), false);
  assert.equal(shouldOpenExternally('C:\\tmp\\setup.exe.', ['.exe'], new Set()), false);
  assert.equal(shouldOpenExternally('C:\\tmp\\setup.exe. .', ['.exe'], new Set()), false);
  assert.equal(shouldOpenExternally('C:\\tmp\\schema.drawio.', TYPES, new Set()), true);
  assert.equal(shouldOpenExternally('C:\\tmp\\schema.drawio ', TYPES, new Set()), true);
  assert.equal(shouldOpenExternally('C:\\tmp\\notes. ', TYPES, new Set()), false);
});

test('bypass key is consumed even when the file is not eligible', () => {
  for (const file of ['C:\\src\\Program.cs', 'C:\\src\\Makefile', 'C:\\tmp\\setup.exe']) {
    const bypass = new Set([bypassKey(file)]);
    assert.equal(shouldOpenExternally(file, ['.exe', '.md'], bypass), false);
    assert.equal(bypass.size, 0, file);
  }
});

test('blocked list is lowercase and dotted', () => {
  for (const t of BLOCKED) {
    assert.match(t, /^\.[a-z0-9-]+$/);
  }
});

test('getout 1 link labels are recognized, other labels are not', () => {
  assert.equal(isLegacyLinkLabel('localhost:8765'), true);
  assert.equal(isLegacyLinkLabel('LocalHost:8765 '), true);
  assert.equal(isLegacyLinkLabel('127.0.0.1:8765'), true);
  assert.equal(isLegacyLinkLabel('localhost:3000'), false);
  assert.equal(isLegacyLinkLabel('notes.md'), false);
  assert.equal(isLegacyLinkLabel(undefined), false);
});
