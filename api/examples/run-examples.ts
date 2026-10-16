import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

/*
 * Replays the example requests against a running API and writes the transcript to docs/api/example-transcript.md.
 * Run (API running in another window):  npm run examples     (from the api folder)
 * It uses unit SN-DEMO-0002, which must have no open card. It leaves one CLOSED card behind and prints the command to remove it.
 */
const base = process.env.API_BASE_URL ?? `http://${process.env.API_HOST ?? '127.0.0.1'}:${process.env.API_PORT ?? '3000'}`;
const REASON: Record<number, string> = {
  200: 'OK', 201: 'Created', 400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found', 409: 'Conflict',
  412: 'Precondition Failed', 422: 'Unprocessable Entity', 428: 'Precondition Required', 500: 'Internal Server Error',
};

interface Answer {
  status: number;
  headers: Headers;
  json: any; // example code only
}

const transcript: string[] = [
  '# Example requests and recorded responses',
  '',
  `Recorded by api/examples/run-examples.ts at ${new Date().toISOString()} against ${base}. Demo authentication only.`,
  '',
];
let n = 0;

async function step(title: string, method: string, path: string, options: { user?: string; ifMatch?: string; body?: unknown } = {}): Promise<Answer> {
  n++;
  const headers: Record<string, string> = {};
  if (options.user) headers['X-Demo-User'] = options.user;
  if (options.ifMatch) headers['If-Match'] = options.ifMatch;
  let body: string | undefined;
  if (options.body !== undefined) {
    body = JSON.stringify(options.body, null, 2);
    headers['Content-Type'] = 'application/json';
  }
  const res = await fetch(base + path, { method, headers, ...(body !== undefined ? { body } : {}) });
  const text = await res.text();
  const json = text ? JSON.parse(text) : undefined;

  const request = [`${method} ${path}`, ...Object.entries(headers).map(([k, v]) => `${k}: ${v}`), ...(body ? ['', body] : [])].join('\n');
  const interesting = ['etag', 'location', 'link', 'allow'].filter((h) => res.headers.has(h)).map((h) => `${h}: ${res.headers.get(h)}`);
  const response = [`${res.status} ${REASON[res.status] ?? ''}`.trim(), ...interesting, ...(json !== undefined ? ['', JSON.stringify(json, null, 2)] : [])].join('\n');

  console.log(`\n[${n}] ${title}\n    ${method} ${path} -> ${res.status}`);
  transcript.push(`## ${n}. ${title}`, '', '```http', request, '```', '', '```http', response, '```', '');
  return { status: res.status, headers: res.headers, json };
}

const etag = (a: Answer): string => a.headers.get('etag') ?? '';

await step('Health check (no user needed)', 'GET', '/api/health');
const opened = await step('Open a card on unit SN-DEMO-0002 (a plain INSERT; a trigger creates the PENDING rows)', 'POST', '/api/cards', {
  user: 'inspector1',
  body: { unit_serial: 'SN-DEMO-0002' },
});
if (opened.status !== 201) {
  console.error('\nCould not open a card on SN-DEMO-0002. If it already has an open card, remove it with: npm run cleanup -- <card id>');
  process.exit(1);
}
const id: number = opened.json._id;
await step('Opening a second card on the same unit is refused by the database (one-active-card rule, error 1062)', 'POST', '/api/cards', {
  user: 'inspector1',
  body: { unit_serial: 'SN-DEMO-0002' },
});
await step('Read the card for display (read view; note the nested unit and the four arrays)', 'GET', `/api/cards/${id}`, { user: 'inspector1' });
const edit = await step('Read the card for editing (edit view; its ETag differs from the read view)', 'GET', `/api/cards/${id}/edit`, { user: 'inspector1' });
await step('A stale ETag is refused with 412 and the current document is returned', 'PUT', `/api/cards/${id}/edit`, {
  user: 'inspector1',
  ifMatch: `"${'0'.repeat(32)}"`,
  body: { checklist: [{ checklist_result_id: edit.json.checklist[0].checklist_result_id, answer_code: 'YES' }] },
});
await step('Only a SUPERVISOR may close', 'POST', `/api/cards/${id}/close`, { user: 'inspector1', ifMatch: etag(edit), body: { disposition: 'PASS' } });
await step('Closing with unanswered checklist items is refused by the database (trigger error 50002)', 'POST', `/api/cards/${id}/close`, {
  user: 'supervisor1',
  ifMatch: etag(edit),
  body: { disposition: 'PASS' },
});
const answered = await step('Write step one: answer every checklist item and record a measurement', 'PUT', `/api/cards/${id}/edit`, {
  user: 'inspector2',
  ifMatch: etag(edit),
  body: {
    checklist: (edit.json.checklist as Array<{ checklist_result_id: number }>).map((i) => ({ checklist_result_id: i.checklist_result_id, answer_code: 'YES' })),
    measurements: [{ measurement_result_id: edit.json.measurements[0].measurement_result_id, result_status: 'RECORDED', measured_value: 1000.125 }],
  },
});
await step('An unknown property is refused by the API before it reaches the database', 'PUT', `/api/cards/${id}/edit`, {
  user: 'inspector1',
  ifMatch: etag(answered),
  body: { bogus: 1 },
});
await step('Write step two: close the card with the ETag from step one', 'POST', `/api/cards/${id}/close`, {
  user: 'supervisor1',
  ifMatch: etag(answered),
  body: { disposition: 'PASS' },
});
const closed = await step('Read the closed card for editing', 'GET', `/api/cards/${id}/edit`, { user: 'inspector1' });
await step('A closed card is read-only: the database lock answers 50022 and the API maps it to 409', 'PUT', `/api/cards/${id}/edit`, {
  user: 'inspector1',
  ifMatch: etag(closed),
  body: { checklist: [{ checklist_result_id: closed.json.checklist[0].checklist_result_id, answer_code: 'NO' }] },
});
await step('List the cards', 'GET', '/api/cards', { user: 'inspector1' });

const file = join(import.meta.dirname, '..', '..', 'docs', 'api', 'example-transcript.md');
writeFileSync(file, transcript.join('\n') + '\n', 'utf8');
console.log(`\nTranscript written to ${file}`);
console.log(`Remove the card this run created with:  npm run cleanup -- ${id}`);
