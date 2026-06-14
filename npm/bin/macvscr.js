#!/usr/bin/env node
'use strict';

// macvscr CLI — launches the native macOS menu-bar binary and manages a user
// LaunchAgent (login start + crash restart).
//
// Three ways to run (progressive):
//   macvscr             run in the FOREGROUND (Ctrl+C to quit)   [default]
//   macvscr run -d      run in the BACKGROUND (terminal returns)
//   macvscr setup       install a login LaunchAgent (runs at login, restarts on crash)
//
// `setup` also copies a stable binary to ~/.macvscr/macvscr (so login launch
// needs no network / no npx) and adds `alias macvscr='npx -y macvscr@latest'`
// to the shell rc if no macvscr command exists.
//
// Why a LaunchAgent (login) not a LaunchDaemon (boot): a menu-bar tray app
// needs the user's GUI session (WindowServer), which exists only after login.

const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PKG = 'macvscr';          // npm package name (== command name)
const CMD = 'macvscr';
const LABEL = 'npm.macvscr';
const BIN = path.join(__dirname, '..', 'binaries', 'macvscr-darwin-arm64');
const AGENT_DIR = path.join(os.homedir(), 'Library', 'LaunchAgents');
const PLIST = path.join(AGENT_DIR, `${LABEL}.plist`);
const STABLE_DIR = path.join(os.homedir(), '.macvscr');
const STABLE_BIN = path.join(STABLE_DIR, 'macvscr');

// --- color ---
const TTY = process.stdout.isTTY && !process.env.NO_COLOR;
const C = TTY
  ? {
      bold: s => `\x1b[1m${s}\x1b[22m`,
      dim: s => `\x1b[2m${s}\x1b[22m`,
      cyan: s => `\x1b[36m${s}\x1b[39m`,
      green: s => `\x1b[32m${s}\x1b[39m`,
      yellow: s => `\x1b[33m${s}\x1b[39m`,
      red: s => `\x1b[31m${s}\x1b[39m`,
    }
  : { bold: s => s, dim: s => s, cyan: s => s, green: s => s, yellow: s => s, red: s => s };
const tag = () => `${C.bold(C.cyan(CMD))}:`;
const hint = s => C.dim(s);

if (process.platform !== 'darwin') {
  console.error(`${tag()} ${C.red('macOS only.')}`);
  process.exit(1);
}
if (!fs.existsSync(BIN)) {
  console.error(`${tag()} native binary not found at ${BIN}`);
  console.error(`      The package looks corrupt — try reinstalling it.`);
  process.exit(1);
}

const uid = process.getuid();
const domainTarget = `gui/${uid}`;
const serviceTarget = `gui/${uid}/${LABEL}`;

// --- helpers ---

function sh(file, args) {
  return spawnSync(file, args, { stdio: 'inherit' });
}
function shOut(file, args) {
  return spawnSync(file, args, { encoding: 'utf8' });
}
function escapeXML(s) {
  return String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}
function isLoaded() {
  return shOut('launchctl', ['print', serviceTarget]).status === 0;
}
function servicePid() {
  if (!isLoaded()) return null;
  const r = shOut('launchctl', ['print', serviceTarget]);
  const m = r.stdout && r.stdout.match(/\bpid\s*=\s*(\d+)/);
  return m ? m[1] : null;
}
function hasCommand() {
  return shOut('sh', ['-c', `command -v ${CMD}`]).status === 0;
}
function rcFile() {
  const shell = process.env.SHELL || '';
  if (shell.endsWith('bash')) return path.join(os.homedir(), '.bashrc');
  return path.join(os.homedir(), '.zshrc'); // macOS default + fallback
}
function isDetach(a) {
  return a.some(x => x === '-d' || x === '--detach' || x === '--background');
}
function stripDetach(a) {
  return a.filter(x => x !== '-d' && x !== '--detach' && x !== '--background');
}

// The alias block is wrapped in stable sentinel markers so future changes to
// the alias command itself never break detection/removal.
const ALIAS_HEAD = '# +++npm:macvscr';
const ALIAS_TAIL = '# ---npm:macvscr';
const ALIAS_LINE = `alias ${CMD}='npx -y ${PKG}@latest'`;
const ALIAS_BLOCK = `\n${ALIAS_HEAD}\n# managed by macvscr setup — remove with \`macvscr uninstall\`\n${ALIAS_LINE}\n${ALIAS_TAIL}\n`;
const ALIAS_BLOCK_RE = /\n# \+\+\+npm:macvscr[\s\S]*?# ---npm:macvscr\n?/;

function aliasInRc() {
  const rc = rcFile();
  try {
    return fs.existsSync(rc) && fs.readFileSync(rc, 'utf8').includes(ALIAS_HEAD);
  } catch (_) {
    return false;
  }
}
function appendAliasBlock() {
  const rc = rcFile();
  try {
    if (fs.existsSync(rc)) fs.appendFileSync(rc, ALIAS_BLOCK);
    else fs.writeFileSync(rc, ALIAS_BLOCK);
    return true;
  } catch (_) {
    return false;
  }
}
function removeAlias() {
  const rc = rcFile();
  if (!fs.existsSync(rc)) return false;
  try {
    const content = fs.readFileSync(rc, 'utf8');
    if (!ALIAS_BLOCK_RE.test(content)) return false;
    fs.writeFileSync(rc, content.replace(ALIAS_BLOCK_RE, ''));
    return true;
  } catch (_) {
    return false;
  }
}
/**
 * Reconcile the shell alias with reality so it never shadows a real command
 * and never goes stale:
 *   - global `macvscr` on PATH -> remove any alias (it would shadow the command)
 *   - no global `macvscr`       -> ensure the alias exists
 * Returns { note, newlyAdded }.
 */
function syncAlias() {
  const rc = rcFile();
  const present = aliasInRc();
  if (hasCommand()) {
    if (present) {
      removeAlias();
      return { note: `${rc} (alias removed — global macvscr on PATH; alias would shadow it)`, newlyAdded: false };
    }
    return { note: 'skipped (global macvscr on PATH)', newlyAdded: false };
  }
  if (present) return { note: `${rc} (already present)`, newlyAdded: false };
  const ok = appendAliasBlock();
  return { note: ok ? `${rc} (added)` : `(could not write ${rc})`, newlyAdded: ok };
}

function plistXML(daemonBin, args) {
  const progArgs = [daemonBin, ...args].map(a => `      <string>${escapeXML(a)}</string>`).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
${progArgs}
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>/tmp/macvscr.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/macvscr.err.log</string>
</dict>
</plist>
`;
}

/** Write the plist (pointing at daemonBin) and bootstrap it. */
function bootstrapService(daemonBin, args) {
  fs.mkdirSync(AGENT_DIR, { recursive: true });
  if (isLoaded()) sh('launchctl', ['bootout', serviceTarget]);
  fs.writeFileSync(PLIST, plistXML(daemonBin, args));
  const r = sh('launchctl', ['bootstrap', domainTarget, PLIST]);
  if (r.status !== 0) {
    console.error(`${tag()} ${C.red('failed to bootstrap the LaunchAgent.')}`);
    process.exit(r.status || 1);
  }
}

// --- service commands ---

function setup(args) {
  console.log(`${tag()} setting up…`);

  fs.mkdirSync(STABLE_DIR, { recursive: true });
  fs.copyFileSync(BIN, STABLE_BIN);
  fs.chmodSync(STABLE_BIN, 0o755);

  const { note: aliasNote, newlyAdded: addedAlias } = syncAlias();

  bootstrapService(STABLE_BIN, args);

  console.log('');
  console.log(`${tag()} ${C.green('setup complete.')}`);
  console.log(`  ${hint('daemon binary:')} ${STABLE_BIN}`);
  console.log(`  ${hint('LaunchAgent:')}   ${PLIST} ${hint('(runs at login; restarts on crash)')}`);
  console.log(`  ${hint('shell alias:')}   ${aliasNote}`);
  if (addedAlias) {
    console.log('');
    console.log(`  ▸ The \`${CMD}\` command won't exist in THIS terminal until you reload the shell:`);
    console.log(`      ${C.cyan(`source ${rcFile()}`)}`);
  }
  console.log('');
  console.log(`  ${hint('How to control macvscr:')}`);
  console.log(`    • ${hint('Quit the app now:')}  click the display icon in the menu bar → Quit`);
  console.log(`    • ${hint('Stop:')}              ${C.cyan(`${CMD} stop`)}`);
  console.log(`    • ${hint('Full teardown:')}     ${C.cyan(`${CMD} uninstall`)}`);
  console.log(`    • ${hint('All options:')}       ${C.cyan(`${CMD} --help`)}`);
}

function uninstall() {
  if (isLoaded()) sh('launchctl', ['bootout', serviceTarget]);
  if (fs.existsSync(PLIST)) fs.unlinkSync(PLIST);
  if (fs.existsSync(STABLE_DIR)) fs.rmSync(STABLE_DIR, { recursive: true, force: true });
  removeAlias();
  sh('pkill', ['-f', STABLE_BIN]);
  sh('pkill', ['-f', BIN]);
  console.log(`${tag()} ${C.green('uninstalled')} ${hint('(LaunchAgent, ~/.macvscr, and shell alias removed).')}`);
}

function start() {
  if (!fs.existsSync(PLIST)) {
    console.error(`${tag()} service not installed. Run \`${C.cyan(`${CMD} setup`)}\` first.`);
    process.exit(1);
  }
  if (isLoaded()) {
    sh('launchctl', ['kickstart', '-k', serviceTarget]);
  } else {
    sh('launchctl', ['bootstrap', domainTarget, PLIST]);
  }
  console.log(`${tag()} ${C.green('service started.')}`);
}

function stop() {
  // Universal: stop the service AND any background instance.
  if (isLoaded()) sh('launchctl', ['bootout', serviceTarget]);
  sh('pkill', ['-f', STABLE_BIN]);
  sh('pkill', ['-f', BIN]);
  console.log(`${tag()} ${C.green('stopped')} ${hint('(service and any background instance).')}`);
}

function status() {
  if (!fs.existsSync(PLIST)) {
    console.log(`${tag()} ${hint('service not installed.')}`);
    return;
  }
  if (!isLoaded()) {
    console.log(`${tag()} ${hint('installed (plist present) but not loaded in this session.')}`);
    return;
  }
  const r = shOut('launchctl', ['print', serviceTarget]);
  const pid = servicePid();
  const lastM = r.stdout && r.stdout.match(/last exit code = (\d+)/);
  console.log(`${tag()} ${C.green(`loaded`)} ${hint(`(${LABEL})`)}`);
  console.log(`  ${pid ? `${C.green(`running`)}${hint(', pid')} ${pid}` : hint('not currently running')}`);
  if (lastM) console.log(`  ${hint('last exit code:')} ${lastM[1]}`);
  console.log(`  ${hint('plist:')} ${PLIST}`);
  console.log(`  ${hint('daemon binary:')} ${fs.existsSync(STABLE_BIN) ? STABLE_BIN : '(~/.macvscr/macvscr missing — run macvscr setup)'}`);
}

// --- run (foreground / background) ---

function guardDuplicate() {
  const pid = servicePid();
  if (pid) {
    console.log(`${tag()} already running as a login service ${hint(`(pid ${pid})`)}. Use the menu-bar icon, or \`${C.cyan(`${CMD} stop`)}\` first.`);
    return true;
  }
  return false;
}

function printRunBanner() {
  console.log(`${tag()} ${C.green('running in the foreground.') } ${hint('Press Ctrl+C to quit.')}`);
  console.log(`  → ${hint('Change resolution live from the display icon in the menu bar.')}`);
  console.log(`  → ${hint('Background instead:')}  ${C.cyan(`${CMD} run -d`)}`);
  console.log(`  → ${hint('Always-on at login:')}   ${C.cyan(`${CMD} setup`)}`);
  console.log(`  → ${hint('More:')}                 ${C.cyan(`${CMD} --help`)}`);
  console.log('');
}

function runForeground(args) {
  if (guardDuplicate()) return;
  printRunBanner();
  const child = spawn(BIN, args, { stdio: 'inherit' });
  child.on('error', err => {
    console.error(`${tag()} ${C.red('failed to launch:')}`, err.message);
    process.exit(1);
  });
  child.on('exit', (code, signal) => {
    if (signal === 'SIGINT' || signal === 'SIGTERM') process.exit(130);
    process.exit(code == null ? 1 : code);
  });
}

function runBackground(args) {
  if (guardDuplicate()) return;
  const child = spawn(BIN, args, { detached: true, stdio: 'ignore' });
  child.on('error', err => {
    console.error(`${tag()} ${C.red('failed to launch:')}`, err.message);
    process.exit(1);
  });
  child.unref();
  console.log(`${tag()} ${C.green('running in background')} ${hint(`(pid ${child.pid}).`)} Stop with: ${C.cyan(`${CMD} stop`)}`);
}

// --- help ---

function printHelp() {
  console.log(`${C.bold(C.cyan('macvscr'))} ${hint('— macOS virtual display tray tool')}`);
  console.log('');
  console.log(C.bold('Three ways to run (progressive):'));
  console.log(`  ${C.cyan('macvscr')}                run in the ${C.bold('FOREGROUND')} (Ctrl+C to quit)  ${hint('[default]')}`);
  console.log(`  ${C.cyan('macvscr run -d')}         run in the ${C.bold('BACKGROUND')} (terminal returns)`);
  console.log(`  ${C.cyan('macvscr setup')}          install a login LaunchAgent ${hint('(runs at login, restarts on crash)')}`);
  console.log('');
  console.log(C.bold('Resolution flags (logical pixels; @2x = physical × 2):'));
  // Delegate the detailed flag list to the native binary's --help.
  const r = spawnSync(BIN, ['--help'], { stdio: 'inherit' });
  if (r.status) process.exit(r.status);
  console.log('');
  console.log(C.bold('Manage the service:'));
  console.log(`  ${C.cyan('macvscr status')}        ${hint('service state')}`);
  console.log(`  ${C.cyan('macvscr start')}         ${hint('start the installed service')}`);
  console.log(`  ${C.cyan('macvscr stop')}          ${hint('stop (service + any background instance)')}`);
  console.log(`  ${C.cyan('macvscr restart')}       ${hint('restart the service')}`);
  console.log(`  ${C.cyan('macvscr uninstall')}     ${hint('full teardown (service + ~/.macvscr + shell alias)')}`);
  console.log('');
  console.log(hint('A menu-bar app needs your GUI session, so it starts at LOGIN, not boot.'));
}

// --- dispatch ---

const args = process.argv.slice(2);
const sub = args[0];
const rest = args.slice(1);

if (sub === 'setup' || sub === 'install') {
  setup(rest);
} else if (sub === 'uninstall') {
  uninstall();
} else if (sub === 'start') {
  start();
} else if (sub === 'stop') {
  stop();
} else if (sub === 'restart') {
  stop();
  setTimeout(start, 700);
} else if (sub === 'status') {
  status();
} else if (sub === 'run') {
  if (isDetach(rest)) runBackground(stripDetach(rest));
  else runForeground(rest);
} else if (sub === 'help' || sub === '-h' || sub === '--help') {
  printHelp();
} else if (sub === undefined) {
  runForeground([]);
} else {
  if (isDetach(args)) runBackground(stripDetach(args));
  else runForeground(args);
}
