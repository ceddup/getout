'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { DEFAULT_TYPES, normalizeTypes } = require('../extension/lib');

const dir = path.join(__dirname, '..', 'extension');
const read = (name) => fs.readFileSync(path.join(dir, name), 'utf8');
const manifest = JSON.parse(read('package.json'));
const nls = { en: JSON.parse(read('package.nls.json')), fr: JSON.parse(read('package.nls.fr.json')) };

test('every %key% of package.json exists in both NLS files', () => {
  const keys = [...read('package.json').matchAll(/"%([^%"]+)%"/g)].map((m) => m[1]);
  assert.ok(keys.length >= 3);
  for (const key of keys) {
    for (const lang of ['en', 'fr']) {
      assert.equal(typeof nls[lang][key], 'string', `${lang}: ${key}`);
    }
  }
});

test('NLS files define the same keys', () => {
  assert.deepEqual(Object.keys(nls.fr).sort(), Object.keys(nls.en).sort());
});

test('default setting equals DEFAULT_TYPES and survives normalizeTypes', () => {
  const setting = manifest.contributes.configuration.properties['getout.externalTypes'];
  assert.equal(setting.scope, 'application'); // a workspace must not widen the list
  assert.deepEqual(setting.default, DEFAULT_TYPES);
  assert.deepEqual(normalizeTypes(setting.default), DEFAULT_TYPES);
});

test('no workspace-trust capability declared (Restricted Mode disables the extension)', () => {
  assert.equal(manifest.capabilities, undefined);
});

test('manifest entry points exist', () => {
  assert.equal(manifest.main, './extension.js');
  assert.ok(fs.existsSync(path.join(dir, manifest.main)));
  const cmd = manifest.contributes.commands.map((c) => c.command);
  assert.deepEqual(cmd, ['getout.openAsText']);
  assert.deepEqual(Object.keys(manifest.contributes.menus).sort(), ['editor/title/context', 'explorer/context']);
});
