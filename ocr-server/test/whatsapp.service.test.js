const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

test("normalizes local Indian phone number formats without duplicating country code", () => {
  const service = require("../src/services/whatsapp.service");
  for (const value of ["9850550645", "+91 98505 50645", "919850550645", "09850550645"]) {
    assert.equal(service.normalizePhoneNumber(value).cleanPhone, "919850550645");
  }
  assert.equal(service.normalizePhoneNumber("1234567890123"), null);
  assert.equal(service.normalizePhoneNumber("12345"), null);
});

test("survives restart, restores session, deduplicates concurrent sends, and records receipts", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "easeinn-wa-test-"));
  const authDir = path.join(root, "auth");
  const dataDir = path.join(root, "data");
  const fakeEngine = path.join(root, "fake-baileys.js");
  const fakeState = path.join(root, "engine-state.json");
  fs.mkdirSync(authDir, { recursive: true });
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(fakeEngine, `
const fs = require('node:fs');
const EventEmitter = require('node:events');
const stateFile = process.env.FAKE_WA_STATE;
module.exports = {
  default: function makeSocket(options) {
    const ev = new EventEmitter();
    const socket = {
      ev, user: { id: '919999999999@s.whatsapp.net', name: 'Test Account' },
      async onWhatsApp(phone) { return [{ jid: phone + '@s.whatsapp.net', exists: true }]; },
      async sendMessage(jid, body) {
        const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
        state.sends += 1; fs.writeFileSync(stateFile, JSON.stringify(state));
        await new Promise(resolve => setTimeout(resolve, 60));
        // Receipt arrives immediately before sendMessage resolves to exercise
        // the race between WhatsApp's event and writing the accepted log.
        ev.emit('messages.update', [{ key: { id: 'message-' + state.sends }, update: { status: 4 } }]);
        return { key: { id: 'message-' + state.sends, fromMe: true, remoteJid: jid }, message: body };
      },
      async logout() { this.ev.emit('connection.update', { connection: 'close', lastDisconnect: { error: { output: { statusCode: 401 } } } }); },
      end() {},
    };
    setTimeout(() => ev.emit('connection.update', { connection: 'open' }), 10);
    setTimeout(() => ev.emit('creds.update'), 15);
    return socket;
  },
  useMultiFileAuthState: async dir => {
    fs.mkdirSync(dir, { recursive: true });
    const file = dir + '/creds.json';
    let creds = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : { registered: false };
    return { state: { creds, keys: {} }, saveCreds: async () => { creds = { registered: true }; fs.writeFileSync(file, JSON.stringify(creds)); } };
  },
  DisconnectReason: { loggedOut: 401, restartRequired: 515 },
  fetchLatestBaileysVersion: async () => ({ version: [2, 3000, 1] }),
  Browsers: { windows: name => ['Windows', name, '1.0'] },
  makeCacheableSignalKeyStore: keys => keys,
};
`);
  fs.writeFileSync(fakeState, JSON.stringify({ sends: 0 }));
  const appScript = `
const assert = require('node:assert/strict');
const service = require('./src/services/whatsapp.service');
(async () => {
  await service.initializeWhatsAppClient();
  await new Promise(r => setTimeout(r, 30));
  assert.equal(service.getStatus().status, 'CONNECTED');
  const args = { recipientPhone: '+91 98505 50645', customMessage: 'hello test', bypassDuplicateCheck: false };
  const [a, b] = await Promise.all([service.sendWhatsAppNotification(args), service.sendWhatsAppNotification(args)]);
  assert.equal([a, b].filter(x => x.accepted).length, 1);
  assert.equal([a, b].filter(x => x.suppressed).length, 1);
  assert.equal(require('node:fs').readFileSync(process.env.FAKE_WA_STATE, 'utf8').match(/sends/g).length, 1);
  const sent = a.accepted ? a : b;
  assert.equal(sent.delivered, false);
  const logs = service.getLogs(10);
  assert.equal(logs.some(x => x.status === 'ACCEPTED' && x.messageId === sent.messageId && x.deliveryStatus === 'READ'), true);
  const selfSend = await service.sendWhatsAppNotification({
    recipientPhone: '919999999999',
    customMessage: 'self test',
    bypassDuplicateCheck: true,
  });
  assert.equal(selfSend.accepted, true);
  assert.equal(selfSend.selfSend, true);
  assert.equal(service.getLogs(10).some(x => x.messageId === selfSend.messageId && x.deliveryStatus === 'READ'), true);
  console.log(JSON.stringify({ ok: true, status: service.getStatus().status, accepted: sent.accepted, delivered: sent.delivered, receiptTracked: true, deduplicated: true }));
  await service.disconnectWhatsAppClient({ preserveSession: true });
})().catch(e => { console.error(e); process.exit(1); });
`;
  const first = spawn(process.execPath, ["-e", appScript], {
    cwd: path.resolve(__dirname, ".."),
    env: { ...process.env, WHATSAPP_AUTH_DIR: authDir, WHATSAPP_DATA_DIR: dataDir, WHATSAPP_ENGINE_MODULE: fakeEngine, FAKE_WA_STATE: fakeState },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  first.stdout.on("data", (chunk) => { stdout += chunk; });
  first.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await new Promise((resolve) => first.on("close", resolve));
  assert.equal(exitCode, 0, stderr);
  assert.match(stdout, /"deduplicated":true/);
  assert.equal(JSON.parse(fs.readFileSync(fakeState, "utf8")).sends, 2);

  const child = spawn(process.execPath, ["-e", `const s=require('./src/services/whatsapp.service'); (async()=>{ await s.initializeWhatsAppClient(); await new Promise(r=>setTimeout(r,35)); const status=s.getStatus(); console.log(JSON.stringify(status)); await s.disconnectWhatsAppClient({preserveSession:true}); })().catch(e=>{console.error(e);process.exit(1)});`], {
    cwd: path.resolve(__dirname, ".."),
    env: { ...process.env, WHATSAPP_AUTH_DIR: authDir, WHATSAPP_DATA_DIR: dataDir, WHATSAPP_ENGINE_MODULE: fakeEngine, FAKE_WA_STATE: fakeState },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let restartOutput = "";
  child.stdout.on("data", (chunk) => { restartOutput += chunk; });
  const childCode = await new Promise((resolve) => child.on("close", resolve));
  assert.equal(childCode, 0);
  const restoredStatus = JSON.parse(restartOutput.trim().split(/\r?\n/).find((line) => line.startsWith("{")));
  assert.equal(restoredStatus.hasPersistedSession, true);
  assert.equal(restoredStatus.status, "CONNECTED");

  const race = spawn(process.execPath, ["-e", `const s=require('./src/services/whatsapp.service'); (async()=>{ const starting=s.initializeWhatsAppClient(); await s.disconnectWhatsAppClient({preserveSession:true}); await starting; await new Promise(r=>setTimeout(r,50)); const status=s.getStatus(); console.log(JSON.stringify({status:status.status,qr:status.hasActiveQr})); process.exit(0); })().catch(e=>{console.error(e);process.exit(1)});`], {
    cwd: path.resolve(__dirname, ".."),
    env: { ...process.env, WHATSAPP_AUTH_DIR: authDir, WHATSAPP_DATA_DIR: dataDir, WHATSAPP_ENGINE_MODULE: fakeEngine, FAKE_WA_STATE: fakeState },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let raceOutput = "";
  let raceError = "";
  race.stdout.on("data", (chunk) => { raceOutput += chunk; });
  race.stderr.on("data", (chunk) => { raceError += chunk; });
  assert.equal(await new Promise((resolve) => race.on("close", resolve)), 0, raceError);
  assert.deepEqual(JSON.parse(raceOutput.trim().split(/\r?\n/).find((line) => line.startsWith("{"))), { status: "DISCONNECTED", qr: false });
  fs.rmSync(root, { recursive: true, force: true });
});
