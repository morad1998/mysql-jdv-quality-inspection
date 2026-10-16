import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import mysql from 'mysql2/promise';
import type { Pool, RowDataPacket } from 'mysql2/promise';
import { createApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';
import { createMySqlDb } from '../src/db.ts';
import type { Db, EditDoc, ReadDoc } from '../src/types.ts';

/*
 * Runs the API against the REAL Docker database (run it with: npm run test:integration).
 * It creates cards through the API on the free units SN-DEMO-0002 and SN-DEMO-0003, then deletes them directly in the
 * database and checks that counts and the ETags of baseline cards 1 and 2 are exactly as they were.
 * Skipped when the database variables are not set.
 */
const enabled = Boolean(process.env.MYSQL_USER && process.env.MYSQL_PASSWORD && process.env.MYSQL_DATABASE);

interface Answer {
  status: number;
  headers: Headers;
  json: any; // test code only
}

describe('integration against the Docker MySQL database', { skip: !enabled }, () => {
  let db: Db;
  let pool: Pool;
  let server: Server;
  let base = '';
  let baseline = '';
  const created: number[] = [];
  let a = 0; // card on unit 3: the full flow
  let b = 0; // card on unit 2: closing with pending items
  let c = 0; // card on unit 3 after a is closed: closed with REJECT
  let inspector2Id = 0;

  async function call(method: string, path: string, options: { user?: string; ifMatch?: string; body?: unknown } = {}): Promise<Answer> {
    const headers: Record<string, string> = {};
    if (options.user) headers['x-demo-user'] = options.user;
    if (options.ifMatch) headers['if-match'] = options.ifMatch;
    let body: string | undefined;
    if (options.body !== undefined) {
      body = JSON.stringify(options.body);
      headers['content-type'] = 'application/json';
    }
    const res = await fetch(base + path, { method, headers, ...(body !== undefined ? { body } : {}) });
    const text = await res.text();
    return { status: res.status, headers: res.headers, json: text ? JSON.parse(text) : undefined };
  }
  const etag = (answer: Answer): string => answer.headers.get('etag') ?? '';

  async function snapshot(): Promise<string> {
    const [counts] = await pool.query<RowDataPacket[]>(
      `SELECT (SELECT COUNT(*) FROM inspection_card) AS cards, (SELECT COUNT(*) FROM measurement_result) AS measurements,
              (SELECT COUNT(*) FROM checklist_result) AS checklist, (SELECT COUNT(*) FROM quality_finding) AS findings,
              (SELECT COUNT(*) FROM attachment_metadata) AS attachments, (SELECT COUNT(*) FROM audit_event) AS audit_events`,
    );
    const [read] = await pool.query<RowDataPacket[]>(
      `SELECT data->>'$._id' AS id, data->>'$._metadata.etag' AS etag FROM inspection_card_dv WHERE data->>'$._id' IN ('1','2') ORDER BY id`,
    );
    const [edit] = await pool.query<RowDataPacket[]>(
      `SELECT data->>'$._id' AS id, data->>'$._metadata.etag' AS etag FROM inspection_card_edit_dv WHERE data->>'$._id' IN ('1','2') ORDER BY id`,
    );
    return JSON.stringify({ counts: counts[0], read, edit });
  }

  async function answerAll(id: number, user: string): Promise<Answer> {
    const edit = await call('GET', `/api/cards/${id}/edit`, { user });
    const doc = edit.json as EditDoc;
    return call('PUT', `/api/cards/${id}/edit`, {
      user,
      ifMatch: etag(edit),
      body: { checklist: (doc.checklist ?? []).map((i) => ({ checklist_result_id: i.checklist_result_id, answer_code: 'YES' })) },
    });
  }

  before(async () => {
    const config = loadConfig();
    db = await createMySqlDb(config.db);
    pool = mysql.createPool({ host: config.db.host, port: config.db.port, user: config.db.user, password: config.db.password, database: config.db.database });
    const [busy] = await pool.query<RowDataPacket[]>(
      `SELECT card_id, unit_id FROM inspection_card WHERE unit_id IN (2, 3) AND card_status IN ('OPEN', 'IN_PROGRESS')`,
    );
    if (busy.length > 0) {
      throw new Error(`Unit 2 or 3 already has an active card (${JSON.stringify(busy)}). Remove it first: npm run cleanup -- <card id>`);
    }
    const inspector2 = await db.findUser('inspector2');
    assert.ok(inspector2, 'the seed user inspector2 must exist');
    inspector2Id = inspector2.user_id;
    baseline = await snapshot();
    server = createServer(createApp(db, () => {}));
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });

  after(async () => {
    server?.close();
    if (!pool) return; // the setup failed before the pool existed; its own error is reported above
    try {
      if (created.length > 0) {
        for (const table of ['attachment_metadata', 'quality_finding', 'checklist_result', 'measurement_result']) {
          await pool.query(`DELETE FROM ${table} WHERE card_id IN (?)`, [created]);
        }
        await pool.query('DELETE FROM inspection_card WHERE card_id IN (?)', [created]);
      }
      assert.equal(await snapshot(), baseline, 'after cleanup the counts and the ETags of cards 1 and 2 must equal the starting state');
    } finally {
      await pool?.end();
      await db?.close();
    }
  });

  it('opens card A on unit 3: a plain INSERT, and the trigger creates the PENDING rows', async () => {
    const r = await call('POST', '/api/cards', { user: 'inspector1', body: { unit_serial: 'SN-DEMO-0003' } });
    assert.equal(r.status, 201, JSON.stringify(r.json));
    const doc = r.json as ReadDoc;
    a = doc._id;
    created.push(a);
    assert.equal(r.headers.get('location'), `/api/cards/${a}`);
    assert.equal(doc.card_status, 'OPEN');
    assert.equal(doc.unit.unit_serial, 'SN-DEMO-0003');
    assert.equal(doc.checklist?.length, 3);
    assert.equal(doc.measurements?.length, 2);
    assert.ok((doc.checklist as Array<{ answer_code: string }>).every((i) => i.answer_code === 'PENDING'));
  });

  it('serves the edit document: smaller than the read document and with its own ETag', async () => {
    const read = await call('GET', `/api/cards/${a}`, { user: 'inspector1' });
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    assert.equal(edit.status, 200);
    assert.equal('unit' in edit.json, false);
    assert.equal(etag(edit), `"${edit.json._metadata.etag}"`);
    assert.notEqual(etag(read), etag(edit));
    assert.equal((await call('GET', '/api/cards/999999', { user: 'inspector1' })).status, 404);
  });

  it('refuses a stale ETag with 412 and returns the current document', async () => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    const r = await call('PUT', `/api/cards/${a}/edit`, {
      user: 'inspector1',
      ifMatch: `"${'0'.repeat(32)}"`,
      body: { checklist: [{ checklist_result_id: edit.json.checklist[0].checklist_result_id, answer_code: 'YES' }] },
    });
    assert.equal(r.status, 412);
    assert.equal(r.json.error.code, 'STALE_ETAG');
    assert.equal(r.json.current.etag, edit.json._metadata.etag);
  });

  it('never forwards an unknown property to the database', async () => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    const r = await call('PUT', `/api/cards/${a}/edit`, { user: 'inspector1', ifMatch: etag(edit), body: { bogus: 1 } });
    assert.equal(r.status, 400);
    assert.equal(r.json.error.code, 'UNKNOWN_PROPERTY');
  });

  it('moves OPEN to IN_PROGRESS through the document', async () => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    const r = await call('PUT', `/api/cards/${a}/edit`, { user: 'inspector1', ifMatch: etag(edit), body: { card_status: 'IN_PROGRESS' } });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.equal(r.json.card_status, 'IN_PROGRESS');
  });

  let beforeAnswers = '';
  it('writes answers and a measurement; the server fills who and when', async () => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector2' });
    beforeAnswers = etag(edit);
    const doc = edit.json as EditDoc;
    const r = await call('PUT', `/api/cards/${a}/edit`, {
      user: 'inspector2',
      ifMatch: etag(edit),
      body: {
        checklist: (doc.checklist ?? []).map((i) => ({ checklist_result_id: i.checklist_result_id, answer_code: 'YES' })),
        measurements: [{ measurement_result_id: doc.measurements?.[0]?.measurement_result_id, result_status: 'RECORDED', measured_value: 1000.125 }],
      },
    });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    const after = r.json as EditDoc;
    assert.ok(after.checklist?.every((i) => i.answer_code === 'YES' && i.answered_by === inspector2Id && i.answered_at !== null));
    assert.equal(after.measurements?.[0]?.result_status, 'RECORDED');
    assert.equal(after.measurements?.[0]?.measured_value, 1000.125);
    assert.equal(after.measurements?.[0]?.recorded_by, inspector2Id);
    assert.notEqual(etag(r), beforeAnswers);
  });

  it('treats the old ETag as stale after that write', async () => {
    const r = await call('PUT', `/api/cards/${a}/edit`, { user: 'inspector1', ifMatch: beforeAnswers, body: { card_status: 'IN_PROGRESS' } });
    assert.equal(r.status, 412);
  });

  it('maps the one-active-card rule (error 1062) to 409', async () => {
    const r = await call('POST', '/api/cards', { user: 'inspector1', body: { unit_serial: 'SN-DEMO-0003' } });
    assert.equal(r.status, 409, JSON.stringify(r.json));
    assert.equal(r.json.error.code, 'ACTIVE_CARD_EXISTS');
    assert.equal(r.json.error.db_errno, 1062);
  });

  it('lets only a SUPERVISOR close', async () => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    const r = await call('POST', `/api/cards/${a}/close`, { user: 'inspector1', ifMatch: etag(edit), body: { disposition: 'PASS' } });
    assert.equal(r.status, 403);
  });

  it('opens card B on unit 2 and maps the database close rule 50002 to 409 while items are PENDING', async () => {
    const opened = await call('POST', '/api/cards', { user: 'inspector1', body: { unit_serial: 'SN-DEMO-0002' } });
    assert.equal(opened.status, 201, JSON.stringify(opened.json));
    b = opened.json._id;
    created.push(b);
    const edit = await call('GET', `/api/cards/${b}/edit`, { user: 'supervisor1' });
    const r = await call('POST', `/api/cards/${b}/close`, { user: 'supervisor1', ifMatch: etag(edit), body: { disposition: 'PASS' } });
    assert.equal(r.status, 409, JSON.stringify(r.json));
    assert.equal(r.json.error.code, 'CHECKLIST_INCOMPLETE');
    assert.equal(r.json.error.db_errno, 50002);
  });

  it('closes card A (the second write of the two-write close)', async () => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'supervisor1' });
    const r = await call('POST', `/api/cards/${a}/close`, { user: 'supervisor1', ifMatch: etag(edit), body: { disposition: 'PASS' } });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.equal(r.json.card_status, 'CLOSED');
    assert.equal(r.json.disposition, 'PASS');
    assert.ok(r.json.closed_by);
    assert.notEqual(etag(r), etag(edit));
  });

  it('a changed answer on a closed card is refused by the database lock (error 50022 -> 409 CARD_FINAL)', async () => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    const doc = edit.json as EditDoc;
    const change = await call('PUT', `/api/cards/${a}/edit`, {
      user: 'inspector1',
      ifMatch: etag(edit),
      body: { checklist: [{ checklist_result_id: doc.checklist?.[0]?.checklist_result_id, answer_code: 'NO' }] },
    });
    assert.equal(change.status, 409, JSON.stringify(change.json));
    assert.equal(change.json.error.code, 'CARD_FINAL');
    assert.equal(change.json.error.db_errno, 50022);
    const unchanged = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    assert.equal(etag(unchanged), etag(edit), 'the refused write must not have changed the card');
  });

  it('closing a closed card again is refused by the API with 409 CARD_FINAL, at any time', async () => {
    // Found by the first integration run: asked straight after the close, the database accepted this write as a no-op
    // (same status, disposition, user and whole-second time). The API now answers before it can reach the database.
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'supervisor1' });
    const again = await call('POST', `/api/cards/${a}/close`, { user: 'supervisor1', ifMatch: etag(edit), body: { disposition: 'PASS' } });
    assert.equal(again.status, 409, JSON.stringify(again.json));
    assert.equal(again.json.error.code, 'CARD_FINAL');
    assert.equal(again.json.error.db_errno, undefined);
    await new Promise((resolve) => setTimeout(resolve, 1100)); // and a second later, when the database would have said 50020
    const later = await call('POST', `/api/cards/${a}/close`, { user: 'supervisor1', ifMatch: etag(edit), body: { disposition: 'PASS' } });
    assert.equal(later.status, 409, JSON.stringify(later.json));
    assert.equal(later.json.error.code, 'CARD_FINAL');
  });

  it('OBSERVATION: a reopen attempt through PUT (card_status IN_PROGRESS on a closed card) is refused', async (t) => {
    const edit = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    const r = await call('PUT', `/api/cards/${a}/edit`, { user: 'inspector1', ifMatch: etag(edit), body: { card_status: 'IN_PROGRESS' } });
    // Either the lock trigger (50020 -> 409) or a CHECK constraint (3819 -> 422) answers first; which one is recorded here.
    t.diagnostic(`reopen attempt answered ${r.status} ${r.json?.error?.code} db_errno=${r.json?.error?.db_errno}`);
    assert.ok(r.status === 409 || r.status === 422, JSON.stringify(r.json));
    const unchanged = await call('GET', `/api/cards/${a}/edit`, { user: 'inspector1' });
    assert.equal(unchanged.json.card_status, 'CLOSED');
    assert.equal(etag(unchanged), etag(edit), 'the refused write must not have changed the card');
  });

  it('opens card C on unit 3 now that A is closed, answers everything and closes it with REJECT', async () => {
    const opened = await call('POST', '/api/cards', { user: 'inspector1', body: { unit_serial: 'SN-DEMO-0003' } });
    assert.equal(opened.status, 201, JSON.stringify(opened.json));
    c = opened.json._id;
    created.push(c);
    const answered = await answerAll(c, 'inspector1');
    assert.equal(answered.status, 200, JSON.stringify(answered.json));
    const r = await call('POST', `/api/cards/${c}/close`, { user: 'supervisor1', ifMatch: etag(answered), body: { disposition: 'REJECT' } });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.equal(r.json.card_status, 'CLOSED');
    assert.equal(r.json.disposition, 'REJECT');
  });

  it('shows the writes in the read view and in the list', async () => {
    const read = await call('GET', `/api/cards/${a}`, { user: 'inspector1' });
    assert.equal(read.status, 200);
    const recorded = (read.json as ReadDoc).measurements as Array<{ result_status: string; measured_value: number | null }>;
    assert.ok(recorded.some((m) => m.result_status === 'RECORDED' && m.measured_value === 1000.125));
    const list = await call('GET', '/api/cards', { user: 'inspector1' });
    const byId = new Map<number, { card_status: string; disposition: string | null }>(list.json.cards.map((x: { card_id: number; card_status: string; disposition: string | null }) => [x.card_id, x]));
    assert.deepEqual(byId.get(a)?.disposition, 'PASS');
    assert.deepEqual(byId.get(c)?.disposition, 'REJECT');
    assert.equal(byId.get(b)?.card_status, 'OPEN');
  });
});
