import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import { createApp } from '../src/app.ts';
import type { EditDoc, ReadDoc } from '../src/types.ts';
import { FakeDb } from './fake-db.ts';

/*
 * HTTP-level tests against FakeDb (see fake-db.ts). They show what the API does with the database signals it was
 * designed for. They do not prove MySQL behaves that way; test/integration.test.ts does.
 */

let server: Server;
let base = '';
let fake: FakeDb;
const logs: string[] = [];

interface Answer {
  status: number;
  headers: Headers;
  json: any; // test code only
}

async function call(method: string, path: string, options: { user?: string; ifMatch?: string; body?: unknown; raw?: string; type?: string } = {}): Promise<Answer> {
  const headers: Record<string, string> = {};
  if (options.user) headers['x-demo-user'] = options.user;
  if (options.ifMatch) headers['if-match'] = options.ifMatch;
  let body: string | undefined;
  if (options.raw !== undefined) {
    body = options.raw;
    headers['content-type'] = options.type ?? 'application/json';
  } else if (options.body !== undefined) {
    body = JSON.stringify(options.body);
    headers['content-type'] = 'application/json';
  }
  const res = await fetch(base + path, { method, headers, ...(body !== undefined ? { body } : {}) });
  const text = await res.text();
  return { status: res.status, headers: res.headers, json: text ? JSON.parse(text) : undefined };
}

const etagOf = (answer: Answer): string => answer.headers.get('etag') ?? '';

before(async () => {
  fake = new FakeDb();
  server = createServer(createApp(fake, (line) => logs.push(line)));
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => {
  server.close();
});

describe('basics', () => {
  it('answers the health check without a user', async () => {
    const a = await call('GET', '/api/health');
    assert.equal(a.status, 200);
    assert.deepEqual(a.json, { status: 'ok' });
  });
  it('needs a known demo user for everything else', async () => {
    assert.equal((await call('GET', '/api/cards')).status, 401);
    assert.equal((await call('GET', '/api/cards')).json.error.code, 'UNAUTHENTICATED');
    const unknown = await call('GET', '/api/cards', { user: 'nobody' });
    assert.equal(unknown.status, 401);
    assert.equal(unknown.json.error.code, 'UNKNOWN_USER');
  });
  it('describes itself at /api without a user (a browser visit shows what to do)', async () => {
    const a = await call('GET', '/api');
    assert.equal(a.status, 200);
    assert.ok(a.json.endpoints.includes('POST /api/cards/:id/close'));
    assert.match(a.json.note, /X-Demo-User/);
  });
  it('answers 404 and 405 correctly', async () => {
    assert.equal((await call('GET', '/api/nothing', { user: 'inspector1' })).status, 404);
    const a = await call('DELETE', '/api/cards/1', { user: 'inspector1' });
    assert.equal(a.status, 405);
    assert.equal(a.headers.get('allow'), 'GET');
    const b = await call('PATCH', '/api/cards/1/edit', { user: 'inspector1' });
    assert.equal(b.status, 405);
    assert.equal(b.headers.get('allow'), 'GET, PUT');
  });
  it('lists cards as summaries', async () => {
    const a = await call('GET', '/api/cards', { user: 'inspector1' });
    assert.equal(a.status, 200);
    assert.deepEqual(a.json.cards[0], { card_id: 1, card_status: 'CLOSED', disposition: 'PASS', unit_serial: 'SN-DEMO-0001' });
  });
  it('rejects a bad id and an unknown card', async () => {
    assert.equal((await call('GET', '/api/cards/abc', { user: 'inspector1' })).json.error.code, 'INVALID_ID');
    assert.equal((await call('GET', '/api/cards/0', { user: 'inspector1' })).status, 400);
    const a = await call('GET', '/api/cards/999', { user: 'inspector1' });
    assert.equal(a.status, 404);
    assert.equal(a.json.error.code, 'CARD_NOT_FOUND');
  });
});

describe('reading', () => {
  it('serves the read document with its ETag and a link to the edit document', async () => {
    const a = await call('GET', '/api/cards/2', { user: 'inspector1' });
    assert.equal(a.status, 200);
    const doc = a.json as ReadDoc;
    assert.equal(doc.unit.unit_serial, 'SN-DEMO-0003');
    assert.equal(etagOf(a), `"${doc._metadata.etag}"`);
    assert.equal(a.headers.get('link'), '</api/cards/2/edit>; rel="edit"');
    assert.equal(a.headers.get('cache-control'), 'no-store');
  });
  it('serves a different, smaller edit document with its own ETag', async () => {
    const read = await call('GET', '/api/cards/2', { user: 'inspector1' });
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    assert.equal(edit.status, 200);
    assert.equal('unit' in edit.json, false);
    assert.equal('opened_by' in edit.json, false);
    assert.notEqual(etagOf(read), etagOf(edit));
  });
});

describe('writing answers (two-write close, step one)', () => {
  it('needs If-Match: 428 when missing, 400 when unusable', async () => {
    const body = { checklist: [{ checklist_result_id: 8, answer_code: 'YES' }] };
    assert.equal((await call('PUT', '/api/cards/2/edit', { user: 'inspector1', body })).status, 428);
    assert.equal((await call('PUT', '/api/cards/2/edit', { user: 'inspector1', body, ifMatch: '*' })).status, 400);
  });
  it('rejects bad bodies before touching the database', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const writesBefore = fake.writes;
    assert.equal((await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), body: { bogus: 1 } })).json.error.code, 'UNKNOWN_PROPERTY');
    assert.equal((await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), body: { checklist: [{ checklist_result_id: 8, answer_code: 'MAYBE' }] } })).status, 422);
    assert.equal((await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), raw: '{not json' })).json.error.code, 'INVALID_JSON');
    assert.equal((await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), raw: '{}', type: 'text/plain' })).status, 415);
    assert.equal((await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit) })).status, 400);
    assert.equal(fake.writes, writesBefore);
  });
  it('rejects a body over the size limit', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const big = JSON.stringify({ checklist: [], padding: 'x'.repeat(70 * 1024) });
    const a = await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), raw: big });
    assert.equal(a.status, 413);
  });
  it('answers 412 with the current document when the ETag is stale', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const a = await call('PUT', '/api/cards/2/edit', {
      user: 'inspector1',
      ifMatch: `"${'0'.repeat(32)}"`,
      body: { checklist: [{ checklist_result_id: 8, answer_code: 'YES' }] },
    });
    assert.equal(a.status, 412);
    assert.equal(a.json.error.code, 'STALE_ETAG');
    assert.equal(a.json.current.etag, edit.json._metadata.etag);
    assert.deepEqual(a.json.current.document, edit.json);
    assert.equal(etagOf(a), etagOf(edit));
  });
  it('refuses a result id that is not on the card with 422', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const a = await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), body: { checklist: [{ checklist_result_id: 1, answer_code: 'YES' }] } });
    assert.equal(a.status, 422);
    assert.equal(a.json.error.code, 'UNKNOWN_RESULT');
  });
  it('writes the answers, fills who and when, and returns a new ETag; the old ETag is then stale', async () => {
    const before = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const items = (before.json as EditDoc).checklist ?? [];
    const answers = items.map((i) => ({ checklist_result_id: i.checklist_result_id, answer_code: 'YES' }));
    const measurementId = (before.json as EditDoc).measurements?.[0]?.measurement_result_id ?? 0;
    const a = await call('PUT', '/api/cards/2/edit', {
      user: 'inspector2',
      ifMatch: etagOf(before),
      body: { card_status: 'IN_PROGRESS', checklist: answers, measurements: [{ measurement_result_id: measurementId, result_status: 'RECORDED', measured_value: 1000.125 }] },
    });
    assert.equal(a.status, 200);
    const doc = a.json as EditDoc;
    assert.equal(doc.card_status, 'IN_PROGRESS');
    assert.ok(doc.checklist?.every((i) => i.answer_code === 'YES' && i.answered_by === 2 && /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{6}$/.test(i.answered_at ?? '')));
    assert.equal(doc.measurements?.[0]?.measured_value, 1000.125);
    assert.notEqual(etagOf(a), etagOf(before));
    const again = await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(before), body: { checklist: [{ checklist_result_id: items[0]?.checklist_result_id, answer_code: 'NO' }] } });
    assert.equal(again.status, 412);
  });
});

describe('closing (two-write close, step two) and the final-card lock', () => {
  it('lets only a SUPERVISOR close', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const a = await call('POST', '/api/cards/2/close', { user: 'inspector1', ifMatch: etagOf(edit), body: { disposition: 'PASS' } });
    assert.equal(a.status, 403);
    assert.equal(a.json.error.code, 'FORBIDDEN');
  });
  it('maps the database close rule 50002 to 409 when an item is unanswered', async () => {
    const opened = await call('POST', '/api/cards', { user: 'inspector1', body: { unit_serial: 'SN-DEMO-0002' } });
    assert.equal(opened.status, 201);
    const id = opened.json._id as number;
    const edit = await call('GET', `/api/cards/${id}/edit`, { user: 'supervisor1' });
    const a = await call('POST', `/api/cards/${id}/close`, { user: 'supervisor1', ifMatch: etagOf(edit), body: { disposition: 'PASS' } });
    assert.equal(a.status, 409);
    assert.equal(a.json.error.code, 'CHECKLIST_INCOMPLETE');
    assert.equal(a.json.error.db_errno, 50002);
  });
  it('closes in two writes: answers first, then the close with the new ETag', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'supervisor1' });
    const a = await call('POST', '/api/cards/2/close', { user: 'supervisor1', ifMatch: etagOf(edit), body: { disposition: 'PASS' } });
    assert.equal(a.status, 200);
    const doc = a.json as EditDoc;
    assert.equal(doc.card_status, 'CLOSED');
    assert.equal(doc.disposition, 'PASS');
    assert.equal(doc.closed_by, 3);
    assert.notEqual(etagOf(a), etagOf(edit));
  });
  it('answers 409 CARD_FINAL for any change to a closed card', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const id = (edit.json as EditDoc).checklist?.[0]?.checklist_result_id ?? 0;
    const change = await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), body: { checklist: [{ checklist_result_id: id, answer_code: 'NO' }] } });
    assert.equal(change.status, 409);
    assert.equal(change.json.error.code, 'CARD_FINAL');
    assert.equal(change.json.error.db_errno, 50022);
  });
  it('refuses closing a closed card again with 409 from the API itself, without a database write', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'supervisor1' });
    const writesBefore = fake.writes;
    const again = await call('POST', '/api/cards/2/close', { user: 'supervisor1', ifMatch: etagOf(edit), body: { disposition: 'PASS' } });
    assert.equal(again.status, 409);
    assert.equal(again.json.error.code, 'CARD_FINAL');
    assert.equal(again.json.error.db_errno, undefined, 'this answer does not come from the database');
    assert.equal(fake.writes, writesBefore);
    const stale = await call('POST', '/api/cards/2/close', { user: 'supervisor1', ifMatch: `"${'0'.repeat(32)}"`, body: { disposition: 'REJECT' } });
    assert.equal(stale.json.error.code, 'CARD_FINAL', 'a final card is reported as final even with a stale ETag');
  });
  it('maps a reopen attempt (card_status IN_PROGRESS on a closed card) to the database lock answer 50020', async () => {
    const edit = await call('GET', '/api/cards/2/edit', { user: 'inspector1' });
    const a = await call('PUT', '/api/cards/2/edit', { user: 'inspector1', ifMatch: etagOf(edit), body: { card_status: 'IN_PROGRESS' } });
    assert.equal(a.status, 409);
    assert.equal(a.json.error.db_errno, 50020);
    assert.equal(etagOf(await call('GET', '/api/cards/2/edit', { user: 'inspector1' })), etagOf(edit));
  });
  it('rejects a bad close body', async () => {
    const edit = await call('GET', '/api/cards/1/edit', { user: 'supervisor1' });
    assert.equal((await call('POST', '/api/cards/1/close', { user: 'supervisor1', ifMatch: etagOf(edit), body: { disposition: 'MAYBE' } })).status, 422);
    assert.equal((await call('POST', '/api/cards/1/close', { user: 'supervisor1', ifMatch: etagOf(edit), body: { disposition: 'PASS', closed_by: 1 } })).json.error.code, 'UNKNOWN_PROPERTY');
  });
});

describe('opening cards', () => {
  it('opens a card, returns 201 with Location and the read document', async () => {
    const a = await call('POST', '/api/cards', { user: 'inspector2', body: { unit_serial: 'SN-DEMO-0003' } });
    assert.equal(a.status, 201);
    assert.equal(a.headers.get('location'), `/api/cards/${a.json._id}`);
    assert.equal(a.json.card_status, 'OPEN');
    assert.equal(a.json.opened_by, 2);
    assert.equal(a.json.checklist.length, 3);
  });
  it('maps the one-active-card rule (1062) to 409', async () => {
    const a = await call('POST', '/api/cards', { user: 'inspector1', body: { unit_serial: 'SN-DEMO-0003' } });
    assert.equal(a.status, 409);
    assert.equal(a.json.error.code, 'ACTIVE_CARD_EXISTS');
    assert.equal(a.json.error.db_errno, 1062);
  });
  it('answers 422 for an unknown unit and a bad body', async () => {
    assert.equal((await call('POST', '/api/cards', { user: 'inspector1', body: { unit_serial: 'SN-NOPE' } })).json.error.code, 'UNKNOWN_UNIT');
    assert.equal((await call('POST', '/api/cards', { user: 'inspector1', body: {} })).status, 422);
  });
});

describe('logging', () => {
  it('logs one line per request without bodies or ETags', () => {
    assert.ok(logs.length > 10);
    assert.ok(logs.every((l) => /^[A-Z]+ \S+ -> \d{3} \(\d+ ms\) user=/.test(l) || l.startsWith('unexpected')));
    assert.ok(!logs.some((l) => /answer_code|etag|If-Match/i.test(l)));
  });
});
