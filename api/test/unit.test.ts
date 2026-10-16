import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { applyClose, applyEdit } from '../src/documents.ts';
import { HttpError, mapDbError } from '../src/errors.ts';
import { formatEtag, readIfMatch } from '../src/etag.ts';
import { mysqlDatetime } from '../src/time.ts';
import type { EditDoc } from '../src/types.ts';
import { validateCloseBody, validateEditBody, validateOpenBody } from '../src/validate.ts';

const ETAG = 'a7406ed8e5cb22ffaabee4c5464c7539';

function doc(): EditDoc {
  return {
    _id: 9,
    _metadata: { etag: ETAG },
    card_status: 'OPEN',
    disposition: null,
    closed_by: null,
    closed_at: null,
    measurements: [{ measurement_result_id: 11, result_status: 'PENDING', measured_value: null, recorded_by: null, recorded_at: null }],
    checklist: [
      { checklist_result_id: 21, answer_code: 'PENDING', answered_by: null, answered_at: null },
      { checklist_result_id: 22, answer_code: 'YES', answered_by: 1, answered_at: '2026-10-16 01:00:00.000000' },
    ],
  };
}

function code(fn: () => unknown): string {
  try {
    fn();
  } catch (err) {
    if (err instanceof HttpError) return `${err.status} ${err.code}`;
    throw err;
  }
  return 'no error';
}

describe('etag', () => {
  it('quotes and parses a strong ETag', () => {
    assert.equal(formatEtag(ETAG), `"${ETAG}"`);
    assert.equal(readIfMatch(`"${ETAG.toUpperCase()}"`), ETAG);
  });
  it('answers 428 when the header is missing and 400 when it is unusable', () => {
    assert.equal(code(() => readIfMatch(undefined)), '428 IF_MATCH_REQUIRED');
    assert.equal(code(() => readIfMatch('')), '428 IF_MATCH_REQUIRED');
    assert.equal(code(() => readIfMatch('*')), '400 INVALID_IF_MATCH');
    assert.equal(code(() => readIfMatch(ETAG)), '400 INVALID_IF_MATCH');
    assert.equal(code(() => readIfMatch(`W/"${ETAG}"`)), '400 INVALID_IF_MATCH');
    assert.equal(code(() => readIfMatch(`"${ETAG}", "${ETAG}"`)), '400 INVALID_IF_MATCH');
  });
});

describe('time', () => {
  it('formats a UTC timestamp the way MySQL writes it in documents', () => {
    assert.match(mysqlDatetime(), /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}$/);
  });
  it('truncates to whole seconds and never rounds (the DATETIME columns keep no fraction)', () => {
    assert.equal(mysqlDatetime(new Date('2026-10-16T02:00:00.123Z')), '2026-10-16 02:00:00.000000');
    assert.equal(mysqlDatetime(new Date('2026-10-16T02:00:00.999Z')), '2026-10-16 02:00:00.000000');
    assert.equal(mysqlDatetime(new Date('2026-10-16T23:59:59.500Z')), '2026-10-16 23:59:59.000000');
  });
});

describe('validateEditBody', () => {
  it('accepts a valid edit', () => {
    const edit = validateEditBody({
      card_status: 'IN_PROGRESS',
      checklist: [{ checklist_result_id: 21, answer_code: 'YES' }],
      measurements: [{ measurement_result_id: 11, result_status: 'RECORDED', measured_value: 1000.125 }],
    });
    assert.equal(edit.card_status, 'IN_PROGRESS');
    assert.equal(edit.checklist.length, 1);
    assert.equal(edit.measurements[0]?.measured_value, 1000.125);
  });
  it('refuses unknown properties before the database can (error 6489 never happens)', () => {
    assert.equal(code(() => validateEditBody({ bogus: 1, checklist: [] })), '400 UNKNOWN_PROPERTY');
    assert.equal(code(() => validateEditBody({ checklist: [{ checklist_result_id: 21, answer_code: 'YES', checklist_definition_id: 2 }] })), '400 UNKNOWN_PROPERTY');
    assert.equal(code(() => validateEditBody({ measurements: [{ measurement_result_id: 11, result_status: 'PENDING', recorded_by: 3 }] })), '400 UNKNOWN_PROPERTY');
  });
  it('refuses bad values with 422', () => {
    assert.equal(code(() => validateEditBody({})), '422 EMPTY_EDIT');
    assert.equal(code(() => validateEditBody({ card_status: 'CLOSED' })), '422 INVALID_VALUE');
    assert.equal(code(() => validateEditBody({ checklist: [{ checklist_result_id: 0, answer_code: 'YES' }] })), '422 INVALID_VALUE');
    assert.equal(code(() => validateEditBody({ checklist: [{ checklist_result_id: 21, answer_code: 'MAYBE' }] })), '422 INVALID_VALUE');
    assert.equal(code(() => validateEditBody({ measurements: [{ measurement_result_id: 11, result_status: 'RECORDED' }] })), '422 INVALID_VALUE');
    assert.equal(code(() => validateEditBody({ measurements: [{ measurement_result_id: 11, result_status: 'RECORDED', measured_value: 1.2345 }] })), '422 INVALID_VALUE');
    assert.equal(code(() => validateEditBody({ measurements: [{ measurement_result_id: 11, result_status: 'RECORDED', measured_value: 12345678 }] })), '422 INVALID_VALUE');
    assert.equal(code(() => validateEditBody({ measurements: [{ measurement_result_id: 11, result_status: 'PENDING', measured_value: 5 }] })), '422 INVALID_VALUE');
    assert.equal(code(() => validateEditBody({ checklist: [{ checklist_result_id: 21, answer_code: 'YES' }, { checklist_result_id: 21, answer_code: 'NO' }] })), '422 DUPLICATE_ENTRY');
    assert.equal(code(() => validateEditBody('text')), '400 INVALID_BODY');
    assert.equal(code(() => validateEditBody([])), '400 INVALID_BODY');
    assert.equal(code(() => validateEditBody(undefined)), '400 INVALID_BODY');
  });
});

describe('validateCloseBody and validateOpenBody', () => {
  it('accepts PASS and REJECT only', () => {
    assert.equal(validateCloseBody({ disposition: 'PASS' }), 'PASS');
    assert.equal(validateCloseBody({ disposition: 'REJECT' }), 'REJECT');
    assert.equal(code(() => validateCloseBody({ disposition: 'MAYBE' })), '422 INVALID_VALUE');
    assert.equal(code(() => validateCloseBody({ disposition: 'PASS', closed_by: 1 })), '400 UNKNOWN_PROPERTY');
  });
  it('accepts a unit serial of safe characters only', () => {
    assert.equal(validateOpenBody({ unit_serial: 'SN-DEMO-0003' }), 'SN-DEMO-0003');
    assert.equal(code(() => validateOpenBody({ unit_serial: "x'; DROP TABLE y;--" })), '422 INVALID_VALUE');
    assert.equal(code(() => validateOpenBody({ unit_serial: '' })), '422 INVALID_VALUE');
    assert.equal(code(() => validateOpenBody({})), '422 INVALID_VALUE');
  });
});

describe('applyEdit and applyClose', () => {
  it('fills who and when on the server and leaves the original untouched', () => {
    const before = doc();
    const after = applyEdit(
      before,
      { card_status: 'IN_PROGRESS', checklist: [{ checklist_result_id: 21, answer_code: 'NO' }], measurements: [{ measurement_result_id: 11, result_status: 'RECORDED', measured_value: 1000.125 }] },
      7,
      '2026-10-16 02:00:00.000000',
    );
    assert.equal(after.card_status, 'IN_PROGRESS');
    assert.deepEqual(after.checklist?.[0], { checklist_result_id: 21, answer_code: 'NO', answered_by: 7, answered_at: '2026-10-16 02:00:00.000000' });
    assert.deepEqual(after.measurements?.[0], { measurement_result_id: 11, result_status: 'RECORDED', measured_value: 1000.125, recorded_by: 7, recorded_at: '2026-10-16 02:00:00.000000' });
    assert.deepEqual(before, doc());
  });
  it('leaves an entry untouched when it changes nothing, so a repeated request is a no-op', () => {
    const after = applyEdit(doc(), { card_status: null, checklist: [{ checklist_result_id: 22, answer_code: 'YES' }], measurements: [] }, 7, '2026-10-16 02:00:00.000000');
    assert.deepEqual(after, doc());
  });
  it('clears who and when when an answer goes back to PENDING', () => {
    const after = applyEdit(doc(), { card_status: null, checklist: [{ checklist_result_id: 22, answer_code: 'PENDING' }], measurements: [] }, 7, '2026-10-16 02:00:00.000000');
    assert.deepEqual(after.checklist?.[1], { checklist_result_id: 22, answer_code: 'PENDING', answered_by: null, answered_at: null });
  });
  it('refuses a result id that is not on the card', () => {
    assert.equal(code(() => applyEdit(doc(), { card_status: null, checklist: [{ checklist_result_id: 999, answer_code: 'YES' }], measurements: [] }, 7, 'x')), '422 UNKNOWN_RESULT');
    assert.equal(code(() => applyEdit(doc(), { card_status: null, checklist: [], measurements: [{ measurement_result_id: 999, result_status: 'PENDING', measured_value: null }] }, 7, 'x')), '422 UNKNOWN_RESULT');
  });
  it('closes with a root-only change', () => {
    const after = applyClose(doc(), 'PASS', 3, '2026-10-16 03:00:00.000000');
    assert.equal(after.card_status, 'CLOSED');
    assert.equal(after.disposition, 'PASS');
    assert.equal(after.closed_by, 3);
    assert.deepEqual(after.checklist, doc().checklist);
    assert.deepEqual(after.measurements, doc().measurements);
  });
});

describe('mapDbError', () => {
  const cases: Array<[number, string, number, string]> = [
    [6494, '', 412, 'STALE_ETAG'],
    [50002, '', 409, 'CHECKLIST_INCOMPLETE'],
    [50003, '', 409, 'CRITICAL_FINDING_OPEN'],
    [50020, '', 409, 'CARD_FINAL'],
    [50021, '', 409, 'CARD_FINAL'],
    [50022, '', 409, 'CARD_FINAL'],
    [1062, "Duplicate entry '3' for key 'inspection_card.uq_card_one_active_per_unit'", 409, 'ACTIVE_CARD_EXISTS'],
    [1062, "Duplicate entry 'x' for key 'work_order.uq_work_order_number'", 409, 'DUPLICATE'],
    [3819, "Check constraint 'chk_card_disposition_final' is violated.", 422, 'RULE_VIOLATED'],
    [1452, 'Cannot add or update a child row: a foreign key constraint fails (`quality_inspection`.`attachment_metadata`, ...)', 422, 'REFERENCE_VIOLATED'],
    [6489, "Path '$.bogus' is not mapped to any column of `quality_inspection`.`inspection_card`.", 400, 'UNKNOWN_PROPERTY'],
    [6497, 'Missing UPDATE tag on `quality_inspection`.`inspection_card`.unit_id, path $.unit.unit_id.', 500, 'READ_ONLY_WRITE'],
  ];
  for (const [errno, text, status, errorCode] of cases) {
    it(`maps ${errno} (${errorCode}) to ${status}`, () => {
      const mapped = mapDbError(Object.assign(new Error(text), { errno, sqlMessage: text }));
      assert.equal(mapped.status, status);
      assert.equal(mapped.code, errorCode);
      assert.equal(mapped.dbErrno, errno);
    });
  }
  it('explains the two close constraints in plain words and names the constraint', () => {
    const mapped = mapDbError(Object.assign(new Error('x'), { errno: 3819, sqlMessage: "Check constraint 'chk_card_close_fields' is violated." }));
    assert.match(mapped.message, /closed_by and closed_at/);
    assert.equal(mapped.extra?.constraint, 'chk_card_close_fields');
  });
  it('never leaks the text of an unknown error', () => {
    const mapped = mapDbError(Object.assign(new Error("Access denied for user 'quality_app'@'172.17.0.1' (using password: YES)"), { errno: 1045 }));
    assert.equal(mapped.status, 500);
    assert.equal(mapped.code, 'INTERNAL_ERROR');
    assert.equal(mapped.dbErrno, undefined);
    assert.doesNotMatch(mapped.message, /quality_app|password|172/);
    assert.equal(mapDbError(undefined).status, 500);
    assert.equal(mapDbError('boom').status, 500);
  });
  it('does not put schema names in the 6489 and 6497 answers', () => {
    const a = mapDbError(Object.assign(new Error('x'), { errno: 6489, sqlMessage: "Path '$.bogus' is not mapped to any column of `quality_inspection`.`inspection_card`." }));
    assert.match(a.message, /\$\.bogus/);
    assert.doesNotMatch(a.message, /quality_inspection|inspection_card/);
    const b = mapDbError(Object.assign(new Error('x'), { errno: 6497, sqlMessage: 'Missing UPDATE tag on `quality_inspection`.`inspection_card`.unit_id' }));
    assert.doesNotMatch(b.message, /quality_inspection|unit_id/);
  });
});
