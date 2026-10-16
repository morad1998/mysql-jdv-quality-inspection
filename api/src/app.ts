import type { IncomingMessage, ServerResponse } from 'node:http';
import { applyClose, applyEdit } from './documents.ts';
import { HttpError, mapDbError } from './errors.ts';
import { formatEtag, readIfMatch } from './etag.ts';
import { mysqlDatetime } from './time.ts';
import type { AppUser, CardSummary, Db, EditDoc, ReadDoc } from './types.ts';
import { validateCloseBody, validateEditBody, validateOpenBody } from './validate.ts';

interface Reply {
  status: number;
  body: unknown;
  headers?: Record<string, string>;
}

interface Ctx {
  req: IncomingMessage;
  params: string[];
  user: AppUser | null;
}

interface Route {
  method: string;
  pattern: RegExp;
  auth: 'none' | 'any' | 'supervisor';
  handle: (ctx: Ctx) => Promise<Reply>;
}

const MAX_BODY_BYTES = 64 * 1024;

function parseId(text: string | undefined): number {
  if (text === undefined || !/^[1-9]\d{0,9}$/.test(text) || Number(text) > 2147483647) {
    throw new HttpError(400, 'INVALID_ID', 'The card id must be a positive integer.');
  }
  return Number(text);
}

function summarize(doc: ReadDoc): CardSummary {
  return { card_id: doc._id, card_status: doc.card_status, disposition: doc.disposition, unit_serial: doc.unit.unit_serial };
}

function staleError(current: EditDoc, dbErrno?: number): HttpError {
  return new HttpError(412, 'STALE_ETAG', 'The card was changed after you read it. The current version is in this response; read it, apply your change to it, and retry.', {
    ...(dbErrno !== undefined ? { dbErrno } : {}),
    extra: { current: { etag: current._metadata.etag, document: current } },
    headers: { etag: formatEtag(current._metadata.etag) },
  });
}

async function readBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  let tooBig = false;
  // Keep reading to the end even when the limit is passed: stopping early would destroy the connection before the answer is sent.
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > MAX_BODY_BYTES) tooBig = true;
    else chunks.push(chunk as Buffer);
  }
  if (tooBig) throw new HttpError(413, 'BODY_TOO_LARGE', `The request body may not exceed ${MAX_BODY_BYTES} bytes.`);
  if (size === 0) return undefined;
  if (!/^application\/json\b/i.test(req.headers['content-type'] ?? '')) {
    throw new HttpError(415, 'UNSUPPORTED_MEDIA_TYPE', 'Send the body as application/json.');
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'INVALID_JSON', 'The request body is not valid JSON.');
  }
}

function send(res: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}): void {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'content-length': Buffer.byteLength(payload),
    ...headers,
  });
  res.end(payload);
}

function errorBody(error: HttpError): unknown {
  return {
    error: { code: error.code, message: error.message, ...(error.dbErrno !== undefined ? { db_errno: error.dbErrno } : {}) },
    ...(error.extra ?? {}),
  };
}

export function createApp(db: Db, log: (line: string) => void = () => {}) {
  /** Turns whatever a database call threw into an HttpError; a stale ETag also returns the current document. */
  async function translate(err: unknown, cardId?: number): Promise<HttpError> {
    if (err instanceof HttpError) return err;
    const mapped = mapDbError(err);
    if (mapped.status === 412 && cardId !== undefined) {
      const current = await db.getEditDocument(cardId);
      if (current) return staleError(current, mapped.dbErrno);
    }
    if (mapped.status === 500) log(`unexpected database error: ${(err as Error)?.message ?? String(err)}`);
    return mapped;
  }

  async function fetchEdit(cardId: number): Promise<EditDoc> {
    const doc = await db.getEditDocument(cardId);
    if (!doc) throw new HttpError(404, 'CARD_NOT_FOUND', `Card ${cardId} does not exist.`);
    return doc;
  }

  const editReply = (doc: EditDoc): Reply => ({ status: 200, body: doc, headers: { etag: formatEtag(doc._metadata.etag) } });

  const routes: Route[] = [
    {
      method: 'GET',
      pattern: /^\/api$/,
      auth: 'none',
      handle: async () => ({
        status: 200,
        body: {
          name: 'MySQL JSON Duality Views quality-inspection demo API',
          note: 'Demo authentication only: send X-Demo-User (inspector1, inspector2 or supervisor1) on every request except /api/health.',
          endpoints: [
            'GET /api/health',
            'GET /api/cards',
            'POST /api/cards',
            'GET /api/cards/:id',
            'GET /api/cards/:id/edit',
            'PUT /api/cards/:id/edit',
            'POST /api/cards/:id/close',
          ],
          reference: 'docs/api/README.md in the repository',
        },
      }),
    },
    {
      method: 'GET',
      pattern: /^\/api\/health$/,
      auth: 'none',
      handle: async () => ({ status: 200, body: { status: 'ok' } }),
    },
    {
      method: 'GET',
      pattern: /^\/api\/cards$/,
      auth: 'any',
      handle: async () => ({ status: 200, body: { cards: (await db.listCards()).map(summarize) } }),
    },
    {
      method: 'POST',
      pattern: /^\/api\/cards$/,
      auth: 'any',
      handle: async ({ req, user }) => {
        const unitSerial = validateOpenBody(await readBody(req));
        let cardId: number | null;
        try {
          cardId = await db.openCard(unitSerial, user!.user_id);
        } catch (err) {
          throw await translate(err);
        }
        if (cardId === null) throw new HttpError(422, 'UNKNOWN_UNIT', `No production unit has the serial ${unitSerial}.`);
        const doc = await db.getReadDocument(cardId);
        if (!doc) throw new Error('The card was inserted but cannot be read back.');
        return {
          status: 201,
          body: doc,
          headers: { location: `/api/cards/${cardId}`, etag: formatEtag(doc._metadata.etag) },
        };
      },
    },
    {
      method: 'GET',
      pattern: /^\/api\/cards\/([^/]+)$/,
      auth: 'any',
      handle: async ({ params }) => {
        const id = parseId(params[0]);
        const doc = await db.getReadDocument(id);
        if (!doc) throw new HttpError(404, 'CARD_NOT_FOUND', `Card ${id} does not exist.`);
        // The read view and the edit view have different ETags: send If-Match values from the edit document only.
        return { status: 200, body: doc, headers: { etag: formatEtag(doc._metadata.etag), link: `</api/cards/${id}/edit>; rel="edit"` } };
      },
    },
    {
      method: 'GET',
      pattern: /^\/api\/cards\/([^/]+)\/edit$/,
      auth: 'any',
      handle: async ({ params }) => editReply(await fetchEdit(parseId(params[0]))),
    },
    {
      method: 'PUT',
      pattern: /^\/api\/cards\/([^/]+)\/edit$/,
      auth: 'any',
      handle: async ({ req, params, user }) => {
        const id = parseId(params[0]);
        const ifMatch = readIfMatch(req.headers['if-match']);
        const edit = validateEditBody(await readBody(req));
        const current = await fetchEdit(id);
        if (current._metadata.etag !== ifMatch) throw staleError(current);
        const patched = applyEdit(current, edit, user!.user_id, mysqlDatetime());
        try {
          await db.writeEditDocument(id, patched);
        } catch (err) {
          throw await translate(err, id);
        }
        return editReply(await fetchEdit(id));
      },
    },
    {
      method: 'POST',
      pattern: /^\/api\/cards\/([^/]+)\/close$/,
      auth: 'supervisor',
      handle: async ({ req, params, user }) => {
        const id = parseId(params[0]);
        const ifMatch = readIfMatch(req.headers['if-match']);
        const disposition = validateCloseBody(await readBody(req));
        const current = await fetchEdit(id);
        // The one place where the API answers before the database. The database accepts a write that changes nothing, so
        // closing a card a second time within the same second (same status, disposition, user and whole-second time) is a
        // silent no-op, and a second later it is refused with error 50020. Found by the integration test; the API makes
        // the answer deterministic. Every other write to a final card is still answered by the database lock.
        if (current.card_status === 'CLOSED' || current.card_status === 'REJECTED') {
          throw new HttpError(409, 'CARD_FINAL', 'The card is already closed. A closed card cannot be changed; open a new card on the unit instead.');
        }
        if (current._metadata.etag !== ifMatch) throw staleError(current);
        const patched = applyClose(current, disposition, user!.user_id, mysqlDatetime());
        try {
          await db.writeEditDocument(id, patched);
        } catch (err) {
          throw await translate(err, id);
        }
        return editReply(await fetchEdit(id));
      },
    },
  ];

  return async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const started = Date.now();
    const method = req.method ?? 'GET';
    let path = '-';
    let status = 500;
    let who = '-';
    try {
      path = new URL(req.url ?? '/', 'http://localhost').pathname;
      const sameMethod = routes.find((r) => r.method === method && r.pattern.test(path));
      if (!sameMethod) {
        const allowed = [...new Set(routes.filter((r) => r.pattern.test(path)).map((r) => r.method))];
        if (allowed.length > 0) {
          throw new HttpError(405, 'METHOD_NOT_ALLOWED', `${method} is not allowed here.`, { headers: { allow: allowed.join(', ') } });
        }
        throw new HttpError(404, 'NOT_FOUND', 'No such endpoint.');
      }

      let user: AppUser | null = null;
      if (sameMethod.auth !== 'none') {
        const name = req.headers['x-demo-user'];
        if (typeof name !== 'string' || name.trim() === '') {
          throw new HttpError(401, 'UNAUTHENTICATED', 'Send the demo user in the X-Demo-User header (demo authentication only).');
        }
        user = await db.findUser(name.trim());
        if (!user) throw new HttpError(401, 'UNKNOWN_USER', 'No active demo user has that name.');
        who = user.username;
        if (sameMethod.auth === 'supervisor' && user.role_code !== 'SUPERVISOR') {
          throw new HttpError(403, 'FORBIDDEN', 'Only a SUPERVISOR may do this.');
        }
      }

      const match = sameMethod.pattern.exec(path);
      const reply = await sameMethod.handle({ req, params: match ? match.slice(1) : [], user });
      status = reply.status;
      send(res, reply.status, reply.body, reply.headers);
    } catch (err) {
      const error = err instanceof HttpError ? err : mapDbError(err);
      if (!(err instanceof HttpError)) log(`unexpected error: ${(err as Error)?.message ?? String(err)}`);
      status = error.status;
      req.resume();
      send(res, error.status, errorBody(error), { ...(error.status === 413 ? { connection: 'close' } : {}), ...(error.headers ?? {}) });
    } finally {
      log(`${method} ${path} -> ${status} (${Date.now() - started} ms) user=${who}`);
    }
  };
}
