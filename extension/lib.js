'use strict';

const path = require('path').win32;

const DEFAULT_TYPES = [
  '.md', '.html', '.pdf', '.png', '.jpg', '.jpeg', '.gif', '.svg',
  '.drawio', '.vsdx', '.docx', '.xlsx', '.pptx', '.odt', '.ods',
];

// Extensions Windows would execute or that carry active content (macros,
// scripts, installers, shortcuts). They are never handed to the shell,
// whatever the user configures.
const BLOCKED = new Set([
  '.ade', '.adp', '.app', '.appref-ms', '.application', '.appx', '.appxbundle',
  '.appinstaller', '.asp', '.bas', '.bat', '.cer', '.chm', '.cmd', '.cnt',
  '.com', '.cpl', '.crt', '.csh', '.der', '.diagcab', '.exe', '.fxp',
  '.gadget', '.grp', '.hlp', '.hpj', '.hta', '.htc', '.inf', '.ins', '.isp',
  '.its', '.jar', '.js', '.jse', '.ksh', '.library-ms', '.lnk', '.mad',
  '.maf', '.mag', '.mam', '.maq', '.mar', '.mas', '.mat', '.mau', '.mav',
  '.maw', '.mcf', '.mda', '.mdb', '.mde', '.mdt', '.mdw', '.mdz', '.msc',
  '.msh', '.msh1', '.msh2', '.mshxml', '.msh1xml', '.msh2xml', '.msi',
  '.msix', '.msixbundle', '.msp', '.mst', '.ops', '.osd', '.pcd', '.pif',
  '.plg', '.prf', '.prg', '.ps1', '.ps1xml', '.ps2', '.ps2xml', '.psc1',
  '.psc2', '.psd1', '.psm1', '.pst', '.reg', '.scf', '.scr', '.sct',
  '.search-ms', '.settingcontent-ms', '.shb', '.shs', '.url', '.vb', '.vbe',
  '.vbp', '.vbs', '.vsmacros', '.vsw', '.ws', '.wsc', '.wsf', '.wsh',
  '.xbap', '.xll', '.xnk',
  // Office macro-enabled formats
  '.docm', '.dotm', '.xlsm', '.xltm', '.xlam', '.pptm', '.potm', '.ppam',
  '.ppsm', '.sldm',
  // Other macro/query-capable Office formats
  '.xlsb', '.xla', '.ppa', '.pps', '.dot', '.xlt', '.iqy', '.slk',
  // Interpreters, launchers, disk images
  '.py', '.pyw', '.pyc', '.pyo', '.pl', '.rb', '.php', '.sh', '.bash', '.ps',
  '.jnlp', '.wsb', '.rdp', '.iso', '.img', '.vhd', '.vhdx',
]);

/**
 * Cleans the user-configured type list: lowercase, leading dot, no
 * duplicates, no blocked extension. Anything that is not an array of
 * strings yields DEFAULT_TYPES.
 */
function normalizeTypes(list) {
  if (!Array.isArray(list) || !list.every((t) => typeof t === 'string')) {
    return DEFAULT_TYPES.slice();
  }
  const out = [];
  for (const raw of list) {
    let ext = raw.trim().toLowerCase();
    if (ext === '' || ext === '.') continue;
    if (!ext.startsWith('.')) ext = '.' + ext;
    if (BLOCKED.has(ext) || out.includes(ext)) continue;
    out.push(ext);
  }
  return out;
}

/** Key identifying a file path in the bypass set (case-insensitive on Windows). */
function bypassKey(fsPath) {
  return path.normalize(fsPath).toLowerCase();
}

/**
 * Extension as Windows resolves it: trailing dots and spaces of the file
 * name are ignored (`x.exe ` and `x.exe.` are `x.exe`).
 */
function effectiveExt(fsPath) {
  const name = path.basename(fsPath).replace(/[. ]+$/, '');
  return path.extname(name).toLowerCase();
}

/**
 * True when the file must be closed in VS Code and opened by Windows.
 * A path present in `bypass` is let through once: its key is consumed
 * whenever the path is checked, eligible or not.
 */
function shouldOpenExternally(fsPath, types, bypass) {
  const key = bypassKey(fsPath);
  if (bypass.delete(key)) return false;
  const ext = effectiveExt(fsPath);
  return ext !== '' && !BLOCKED.has(ext) && types.includes(ext);
}

module.exports = {
  DEFAULT_TYPES,
  BLOCKED,
  normalizeTypes,
  shouldOpenExternally,
  bypassKey,
};
