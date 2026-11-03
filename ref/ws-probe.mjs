// 宿主侧无头复现手机链路：message → sent → subscribed → event(delta/committed)
import { readFileSync } from 'node:fs';

const { token } = JSON.parse(readFileSync(new URL('./probe-token.json', import.meta.url)));
const url = 'ws://127.0.0.1:3090/ws/mobile';
const ws = new WebSocket(url, ['dsh-mobile-v1', `dsh-auth.${token}`]);
const t0 = Date.now();
const ts = () => `${((Date.now() - t0) / 1000).toFixed(1)}s`;
let deltaCount = 0;
let sid = null;
let done = false;

ws.onopen = () => console.log(ts(), 'OPEN (subprotocols sent: dsh-mobile-v1 + dsh-auth.***)');
ws.onmessage = (ev) => {
  const f = JSON.parse(ev.data);
  const { kind, data } = f;
  if (kind === 'event') {
    const t = data.type;
    if (t === 'chat.message.delta') {
      deltaCount++;
      if (deltaCount <= 2 || deltaCount % 20 === 0) {
        console.log(ts(), `event delta#${deltaCount}`, JSON.stringify(data.data).slice(0, 120));
      }
    } else if (t === 'chat.message.committed') {
      console.log(ts(), 'event committed', JSON.stringify(data.data));
      done = true;
    } else if (t === 'chat.turn.failed') {
      console.log(ts(), 'event turn.failed', JSON.stringify(data.data));
      done = true;
    } else {
      console.log(ts(), 'event', t, JSON.stringify(data.data ?? data).slice(0, 100));
    }
  } else if (kind === 'sent') {
    sid = data.sessionId;
    console.log(ts(), 'sent', 'sessionId=', sid, 'accepted=', data.accepted, 'rid=', f.requestId);
  } else if (kind === 'subscribed') {
    console.log(ts(), 'subscribed rid=', f.requestId);
  } else if (kind === 'hello') {
    console.log(ts(), 'hello protocol=', data.protocol, 'authenticated=', data.authenticated);
    const rid = `probe-${Date.now()}`;
    ws.send(JSON.stringify({ type: 'message', requestId: rid, mode: 'queue', content: [{ type: 'text', text: 'Reply with exactly one word: PONG' }], clientTimeZone: 'Asia/Shanghai' }));
    console.log(ts(), '→ message sent (rid', rid + ')');
  } else if (kind === 'pong') {
    /* ignore */
  } else {
    console.log(ts(), kind, JSON.stringify(data).slice(0, 120));
  }
};
ws.onerror = (e) => console.log(ts(), 'ERROR', e.message ?? e);
ws.onclose = (e) => { console.log(ts(), 'CLOSE', e.code, e.reason); process.exit(0); };

setTimeout(() => {
  if (sid && !done) {
    console.log(ts(), '-- turn not finished, pulling history for', sid);
    fetch(`http://127.0.0.1:3090/api/v1/chat/sessions/${sid}/messages`, { headers: { Authorization: `Bearer ${token}` } })
      .then(r => r.json())
      .then(j => console.log(ts(), 'history events:', (j.events ?? []).length));
  }
  console.log(ts(), 'probe exit');
  process.exit(0);
}, 30000);
