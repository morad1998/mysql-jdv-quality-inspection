import { HttpError } from './errors.ts';
import type { Disposition, EditDoc, EditRequest } from './types.ts';

/**
 * Applies an edit to a copy of the current edit document. The server fills who and when; the client never sends them.
 * An entry that does not change the stored value is left untouched, so repeating a request changes nothing.
 * The API does not check whether the card is final: the database lock (errors 50020 to 50022) answers that.
 */
export function applyEdit(current: EditDoc, edit: EditRequest, userId: number, now: string): EditDoc {
  const doc: EditDoc = structuredClone(current);

  if (edit.card_status === 'IN_PROGRESS') doc.card_status = 'IN_PROGRESS';

  for (const change of edit.checklist) {
    const item = (doc.checklist ?? []).find((x) => x.checklist_result_id === change.checklist_result_id);
    if (!item) {
      throw new HttpError(422, 'UNKNOWN_RESULT', `Checklist result ${change.checklist_result_id} does not belong to card ${doc._id}.`);
    }
    if (item.answer_code === change.answer_code) continue;
    item.answer_code = change.answer_code;
    if (change.answer_code === 'PENDING') {
      item.answered_by = null;
      item.answered_at = null;
    } else {
      item.answered_by = userId;
      item.answered_at = now;
    }
  }

  for (const change of edit.measurements) {
    const item = (doc.measurements ?? []).find((x) => x.measurement_result_id === change.measurement_result_id);
    if (!item) {
      throw new HttpError(422, 'UNKNOWN_RESULT', `Measurement result ${change.measurement_result_id} does not belong to card ${doc._id}.`);
    }
    if (item.result_status === change.result_status && item.measured_value === change.measured_value) continue;
    item.result_status = change.result_status;
    item.measured_value = change.measured_value;
    if (change.result_status === 'PENDING') {
      item.recorded_by = null;
      item.recorded_at = null;
    } else {
      item.recorded_by = userId;
      item.recorded_at = now;
    }
  }
  return doc;
}

/** A root-only change: the card becomes CLOSED with the given disposition. The close rules are the database's. */
export function applyClose(current: EditDoc, disposition: Disposition, userId: number, now: string): EditDoc {
  const doc: EditDoc = structuredClone(current);
  doc.card_status = 'CLOSED';
  doc.disposition = disposition;
  doc.closed_by = userId;
  doc.closed_at = now;
  return doc;
}
