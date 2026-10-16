export interface HttpErrorOptions {
  dbErrno?: number;
  extra?: Record<string, unknown>;
  headers?: Record<string, string>;
}

export class HttpError extends Error {
  status: number;
  code: string;
  dbErrno: number | undefined;
  extra: Record<string, unknown> | undefined;
  headers: Record<string, string> | undefined;

  constructor(status: number, code: string, message: string, options: HttpErrorOptions = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.dbErrno = options.dbErrno;
    this.extra = options.extra;
    this.headers = options.headers;
  }
}

const CONSTRAINT_TEXT: Record<string, string> = {
  chk_card_disposition_final: 'A closed card needs a disposition, and only a final card may have one.',
  chk_card_close_fields: 'closed_by and closed_at must be set exactly when the card is closed.',
  chk_measurement_result_status: 'The measurement status is not one of PENDING, RECORDED or NOT_APPLICABLE.',
  chk_measurement_result_value: 'A recorded measurement needs a value; other statuses must not have one.',
  chk_measurement_result_who: 'A measurement that is not PENDING needs who recorded it and when.',
  chk_checklist_result_answer: 'The checklist answer is not one of PENDING, YES, NO or NOT_APPLICABLE.',
  chk_checklist_result_who: 'A checklist answer that is not PENDING needs who answered and when.',
};

/**
 * Maps a MySQL error to the HTTP answer the API gives. The error NUMBER decides; the text is never forwarded
 * except for the constraint name and the document path, which carry no schema or credential information.
 * Unknown errors become a plain 500 without details.
 */
export function mapDbError(err: unknown): HttpError {
  const e = (err ?? {}) as { errno?: unknown; sqlMessage?: unknown; message?: unknown };
  const errno = typeof e.errno === 'number' ? e.errno : undefined;
  const text = typeof e.sqlMessage === 'string' ? e.sqlMessage : typeof e.message === 'string' ? e.message : '';

  switch (errno) {
    case 6494:
      return new HttpError(412, 'STALE_ETAG', 'The card was changed after you read it. Read it again and retry.', { dbErrno: 6494 });
    case 50002:
      return new HttpError(409, 'CHECKLIST_INCOMPLETE', 'The card cannot be closed: at least one checklist item is still unanswered.', { dbErrno: 50002 });
    case 50003:
      return new HttpError(409, 'CRITICAL_FINDING_OPEN', 'The card cannot be closed: an open CRITICAL finding exists.', { dbErrno: 50003 });
    case 50020:
    case 50021:
    case 50022:
      return new HttpError(409, 'CARD_FINAL', 'A closed card cannot be changed. Open a new card on the unit instead.', { dbErrno: errno });
    case 1062:
      if (text.includes('uq_card_one_active_per_unit')) {
        return new HttpError(409, 'ACTIVE_CARD_EXISTS', 'The unit already has an open card. Close it before opening another.', { dbErrno: 1062 });
      }
      return new HttpError(409, 'DUPLICATE', 'A record with the same unique value already exists.', { dbErrno: 1062 });
    case 3819: {
      const name = /Check constraint '([^']+)'/.exec(text)?.[1];
      const message = (name !== undefined ? CONSTRAINT_TEXT[name] : undefined) ?? `A database rule was violated${name ? ` (${name})` : ''}.`;
      return new HttpError(422, 'RULE_VIOLATED', message, { dbErrno: 3819, extra: name ? { constraint: name } : {} });
    }
    case 1452:
      return new HttpError(422, 'REFERENCE_VIOLATED', 'The data refers to a record that does not exist or belongs to another card.', { dbErrno: 1452 });
    case 6489: {
      const path = /Path '([^']+)'/.exec(text)?.[1];
      return new HttpError(400, 'UNKNOWN_PROPERTY', `The document contains a property the view does not accept${path ? `: ${path}` : ''}.`, { dbErrno: 6489 });
    }
    case 6497:
      return new HttpError(500, 'READ_ONLY_WRITE', 'The API tried to write through a read-only view. This is a bug in the API.', { dbErrno: 6497 });
    default:
      return new HttpError(500, 'INTERNAL_ERROR', 'Unexpected error.');
  }
}
