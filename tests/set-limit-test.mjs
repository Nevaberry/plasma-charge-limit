// SPDX-FileCopyrightText: 2026 Antti Jalomäki
// SPDX-License-Identifier: MIT
// Exercise the actual QML JavaScript with shell commands on an isolated PATH.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import vm from 'node:vm';

const qml = readFileSync(new URL('../package/contents/ui/main.qml', import.meta.url), 'utf8');
const functions = ['quote', 'setLimit'].map(name => {
    const match = qml.match(new RegExp(`^    function ${name}\\([^]*?^    }`, 'm'));
    assert.ok(match, `${name} must exist in main.qml`);
    return match[0];
}).join('\n');

function widget(t, helperState) {
    const bin = mkdtempSync(join(tmpdir(), 'charge-limit-test-'));
    t.after(() => rmSync(bin, { recursive: true, force: true }));
    const log = join(bin, 'pkexec-args');
    const commands = [];
    const queue = [];
    let refreshes = 0;
    const context = vm.createContext({
        helperState,
        installedHelper: '/usr/local/libexec/plasma-charge-limit-helper',
        bundledHelper: "/tmp/charge limit's $(false)/chargelimit-helper",
        pending: 0,
        error: 'previous error',
        i18n: (text, value) => text.replace('%1', value),
        refresh: () => refreshes++,
        run: (command, done) => {
            commands.push(command);
            queue.push({ command, done });
        },
    });
    vm.runInContext(functions, context);
    return {
        context, commands,
        get refreshes() { return refreshes; },
        get args() { return readFileSync(log, 'utf8').trimEnd().split('\n'); },
        installPkexec(code = 0, stderr = '') {
            writeFileSync(join(bin, 'pkexec'),
                `#!/bin/sh\nprintf '%s\\n' "$@" > "$PKEXEC_LOG"\nprintf '%s\\n' '${stderr}' >&2\nexit ${code}\n`,
                { mode: 0o755 });
            writeFileSync(join(bin, 'gdbus'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
        },
        step() {
            assert.ok(queue.length, 'a shell command must be pending');
            const { command, done } = queue.shift();
            const result = spawnSync('/bin/sh', ['-c', command], {
                env: { PATH: bin, PKEXEC_LOG: log, LC_ALL: 'C' }, encoding: 'utf8',
            });
            assert.ifError(result.error);
            if (done) done(result.status, result.stdout.trim(), result.stderr.trim());
        },
        drain() { while (queue.length) this.step(); },
    };
}

for (const state of ['setup', 'outdated', 'ready']) {
    test(`${state}: missing pkexec shows instructions and recovers after installation`, t => {
        const app = widget(t, state);
        app.context.setLimit(80);
        assert.equal(app.context.pending, 80);
        assert.equal(app.context.error, '');
        app.drain();
        assert.equal(app.context.pending, 0);
        assert.match(app.context.error, /pkexec is missing.*sudo apt install pkexec/);
        assert.equal(app.commands.length, 1, 'must not attempt a privileged command');
        assert.equal(app.refreshes, 0);

        app.installPkexec();
        app.context.setLimit(90);
        app.step();
        assert.equal(app.context.pending, 90, 'remain busy after the dependency check');
        assert.equal(app.context.error, '');
        app.drain();
        assert.deepEqual(app.args, state === 'ready'
            ? [app.context.installedHelper, 'set', '90']
            : ['/bin/bash', app.context.bundledHelper, 'install', '90']);
        assert.equal(app.context.pending, 0);
        assert.equal(app.context.error, '');
        assert.equal(app.refreshes, 1);
        assert.ok(app.commands.some(command => command.startsWith('gdbus ')));
    });

    for (const code of [1, 126, 127]) {
        test(`${state}: pkexec exit ${code} retains authentication error handling`, t => {
            const app = widget(t, state);
            app.installPkexec(code, 'Authorization failed');
            app.context.setLimit(80);
            app.drain();
            assert.equal(app.context.pending, 0);
            assert.equal(app.context.error, code === 126
                ? '' : 'Could not change the charge limit.\nAuthorization failed');
            assert.equal(app.refreshes, 1);
            assert.ok(!app.commands.some(command => command.startsWith('gdbus ')));
        });
    }
}
