'use strict';

// Devspaces helper: carries out requests the devspaces script drops in
// ~/Library/Application Support/devspaces/requests.
//
// Why it exists: a window opened from inside VS Code appears on the macOS Space
// the user is looking at. The `code` command does not: it brings VS Code to the
// front before making the window, and macOS then jumps to a Space that already
// has a VS Code window, so every reopened window piles onto one Space.
//
// Trust boundary: the requests folder is the user's own (0700, owner checked),
// the same boundary as running `code <folder>`. Requests are still validated:
// fixed file names, a short age limit, and folders must be real directories
// (or .code-workspace files) inside the home folder.

const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');

const BASE = path.join(os.homedir(), 'Library', 'Application Support', 'devspaces');
const REQUESTS = path.join(BASE, 'requests');
const RESPONSES = path.join(BASE, 'responses');
const READY = path.join(BASE, 'ready');
const MAX_AGE_MS = 60 * 1000;
const REQUEST_FILE = /^[A-Za-z0-9_-]{1,64}\.json$/;
const REQUEST_ID = /^[A-Za-z0-9_-]{1,64}$/;

let log;
let queue = Promise.resolve();

function activate(context) {
    if (process.platform !== 'darwin') {
        return;
    }
    log = vscode.window.createOutputChannel('Devspaces');
    context.subscriptions.push(log);
    for (const dir of [BASE, REQUESTS, RESPONSES, READY]) {
        fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    }
    if (!isPrivateDir(BASE) || !isPrivateDir(REQUESTS)) {
        log.appendLine(`Refusing requests: ${BASE} must be owned by you and closed to other users.`);
        return;
    }

    const marker = path.join(READY, `${process.pid}.json`);
    const folder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? null;
    fs.writeFileSync(marker, JSON.stringify({ pid: process.pid, folder, at: Date.now() }), { mode: 0o600 });
    context.subscriptions.push({ dispose: () => fs.rmSync(marker, { force: true }) });

    const watcher = fs.watch(REQUESTS, () => scan());
    context.subscriptions.push({ dispose: () => watcher.close() });
    scan();
}

function isPrivateDir(dir) {
    const stat = fs.statSync(dir);
    return stat.isDirectory() && stat.uid === process.getuid() && (stat.mode & 0o022) === 0;
}

function scan() {
    queue = queue.then(async () => {
        let names;
        try {
            names = fs.readdirSync(REQUESTS).filter((name) => REQUEST_FILE.test(name)).sort();
        } catch (error) {
            log.appendLine(`Could not read requests: ${error.message}`);
            return;
        }
        for (const name of names) {
            await handle(name);
        }
    });
}

async function handle(name) {
    // Every window runs this extension; the atomic rename lets exactly one claim a request.
    const source = path.join(REQUESTS, name);
    if (!meantForThisWindow(source)) {
        return;
    }
    const claimed = `${source}.${process.pid}.claimed`;
    try {
        fs.renameSync(source, claimed);
    } catch {
        return;
    }
    let request;
    try {
        request = JSON.parse(fs.readFileSync(claimed, 'utf8'));
    } catch {
        log.appendLine(`Ignored unreadable request ${name}.`);
        return;
    } finally {
        fs.rmSync(claimed, { force: true });
    }
    if (!request || request.v !== 1 || typeof request.id !== 'string' || !REQUEST_ID.test(request.id)) {
        log.appendLine(`Ignored malformed request ${name}.`);
        return;
    }
    const age = Date.now() - request.at;
    if (typeof request.at !== 'number' || age > MAX_AGE_MS || age < -5000) {
        respond(request.id, false, 'Request expired.');
        return;
    }
    try {
        // quit and close answer for themselves, before the window goes away
        if (await perform(request) !== 'answered') {
            respond(request.id, true);
        }
    } catch (error) {
        log.appendLine(`Request ${request.id} failed: ${error.message}`);
        respond(request.id, false, error.message);
    }
}

async function perform(request) {
    switch (request.type) {
        case 'open': {
            const target = resolveTarget(request.path);
            log.appendLine(`Opening ${target} in a new window.`);
            const uri = vscode.Uri.file(target);
            await vscode.commands.executeCommand('vscode.openFolder', uri, { forceNewWindow: true });
            return;
        }
        case 'devtools':
            await openBrowserDevTools(typeof request.title === 'string' ? request.title : '');
            return;
        case 'check-update':
            log.appendLine('Checking for a VS Code update.');
            await vscode.commands.executeCommand('update.checkForUpdate');
            return;
        case 'close':
            if (request.folder === undefined) {
                throw new Error('Close needs a folder.');
            }
            log.appendLine('Closing this window.');
            respond(request.id, true);
            await vscode.commands.executeCommand('workbench.action.closeWindow');
            return 'answered';
        case 'quit':
            log.appendLine('Quitting VS Code.');
            // Answer before quitting; nothing runs after the command.
            respond(request.id, true);
            await vscode.commands.executeCommand('workbench.action.quit');
            return 'answered';
        default:
            throw new Error('Unknown request type.');
    }
}

// A request naming a folder is for the window showing that folder; the rest are for any window.
function meantForThisWindow(file) {
    let folder;
    try {
        folder = JSON.parse(fs.readFileSync(file, 'utf8')).folder;
    } catch {
        return false; // gone (another window took it) or not written yet
    }
    if (folder === undefined) {
        return true;
    }
    const mine = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    try {
        return Boolean(mine) && fs.realpathSync(mine) === folder;
    } catch {
        return false;
    }
}

// VS Code saves a browser tab's address but not its DevTools, so reopen them on the
// browser tab that was in front. The tab API cannot see browser tabs' addresses;
// they show as tabs with no known input, matched here by page title.
async function openBrowserDevTools(title) {
    const ordinals = ['First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth'];
    const groups = vscode.window.tabGroups.all;
    const unknownInput = (group) => group.activeTab && group.activeTab.input === undefined;
    // The saved title picks the tab; a dev server that is down changes the title, so fall back
    // to the only front tab VS Code cannot otherwise describe.
    const titled = groups.filter((group) => unknownInput(group) && group.activeTab.label === title);
    const untyped = groups.filter(unknownInput);
    const group = titled.length === 1 ? titled[0] : untyped.length === 1 ? untyped[0] : undefined;
    // viewColumn counts groups in the order they appear, as the focus commands do.
    const column = group?.viewColumn;
    if (!column || column > ordinals.length) {
        throw new Error('No browser tab in front.');
    }
    const previous = vscode.window.tabGroups.activeTabGroup.viewColumn;
    await vscode.commands.executeCommand(`workbench.action.focus${ordinals[column - 1]}EditorGroup`);
    await vscode.commands.executeCommand('workbench.action.browser.toggleDevTools');
    if (previous && previous !== column && previous <= ordinals.length) {
        await vscode.commands.executeCommand(`workbench.action.focus${ordinals[previous - 1]}EditorGroup`);
    }
}

function resolveTarget(requested) {
    if (typeof requested !== 'string' || !path.isAbsolute(requested)) {
        throw new Error('Path must be absolute.');
    }
    const home = fs.realpathSync(os.homedir());
    const real = fs.realpathSync(requested);
    if (real !== home && !real.startsWith(home + path.sep)) {
        throw new Error('Path must be inside the home folder.');
    }
    const stat = fs.statSync(real);
    if (stat.isDirectory() || (stat.isFile() && real.endsWith('.code-workspace'))) {
        return real;
    }
    throw new Error('Path must be a folder or a .code-workspace file.');
}

function respond(id, ok, error) {
    const file = path.join(RESPONSES, `${id}.json`);
    const body = JSON.stringify({ id, ok, error: error ?? null, pid: process.pid, at: Date.now() });
    try {
        // write then rename, so the script never reads a half-written answer
        const partial = path.join(RESPONSES, `.${id}.${process.pid}.tmp`);
        fs.writeFileSync(partial, body, { mode: 0o600 });
        fs.renameSync(partial, file);
    } catch (writeError) {
        log.appendLine(`Could not answer ${id}: ${writeError.message}`);
    }
}

function deactivate() {}

module.exports = { activate, deactivate };
