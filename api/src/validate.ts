import { HttpError } from './errors.ts';
import type { AnswerCode, ChecklistEdit, Disposition, EditRequest, MeasurementEdit, ResultStatus } from './types.ts';

const ANSWER_CODES: readonly string[] = ['PENDING', 'YES', 'NO', 'NOT_APPLICABLE'];
const RESULT_STATUSES: readonly string[] = ['PENDING', 'RECORDED', 'NOT_APPLICABLE'];

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** The API never forwards a property it does not know, so MySQL never has to refuse one (error 6489). */
function onlyKeys(obj: Record<string, unknown>, allowed: readonly string[], where: string): void {
  for (const key of Object.keys(obj)) {
    if (!allowed.includes(key)) {
      throw new HttpError(400, 'UNKNOWN_PROPERTY', `Property '${key}' is not accepted ${where}.`);
    }
  }
}

function positiveInt(value: unknown, label: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 2147483647) {
    throw new HttpError(422, 'INVALID_VALUE', `${label} must be a positive integer.`);
  }
  return value;
}

function requireObject(body: unknown): Record<string, unknown> {
  if (!isObject(body)) throw new HttpError(400, 'INVALID_BODY', 'Send a JSON object as the request body.');
  return body;
}

export function validateEditBody(body: unknown): EditRequest {
  const obj = requireObject(body);
  onlyKeys(obj, ['card_status', 'checklist', 'measurements'], 'in the request');

  let cardStatus: 'IN_PROGRESS' | null = null;
  if (obj.card_status !== undefined) {
    if (obj.card_status !== 'IN_PROGRESS') {
      throw new HttpError(422, 'INVALID_VALUE', "card_status may only be set to 'IN_PROGRESS'. Use the close endpoint to close a card.");
    }
    cardStatus = 'IN_PROGRESS';
  }

  const checklist: ChecklistEdit[] = [];
  if (obj.checklist !== undefined) {
    if (!Array.isArray(obj.checklist)) throw new HttpError(422, 'INVALID_VALUE', 'checklist must be an array.');
    const seen = new Set<number>();
    for (const raw of obj.checklist as unknown[]) {
      if (!isObject(raw)) throw new HttpError(422, 'INVALID_VALUE', 'Each checklist entry must be an object.');
      onlyKeys(raw, ['checklist_result_id', 'answer_code'], 'in a checklist entry');
      const id = positiveInt(raw.checklist_result_id, 'checklist_result_id');
      if (typeof raw.answer_code !== 'string' || !ANSWER_CODES.includes(raw.answer_code)) {
        throw new HttpError(422, 'INVALID_VALUE', `answer_code must be one of ${ANSWER_CODES.join(', ')}.`);
      }
      if (seen.has(id)) throw new HttpError(422, 'DUPLICATE_ENTRY', `checklist_result_id ${id} appears twice.`);
      seen.add(id);
      checklist.push({ checklist_result_id: id, answer_code: raw.answer_code as AnswerCode });
    }
  }

  const measurements: MeasurementEdit[] = [];
  if (obj.measurements !== undefined) {
    if (!Array.isArray(obj.measurements)) throw new HttpError(422, 'INVALID_VALUE', 'measurements must be an array.');
    const seen = new Set<number>();
    for (const raw of obj.measurements as unknown[]) {
      if (!isObject(raw)) throw new HttpError(422, 'INVALID_VALUE', 'Each measurement entry must be an object.');
      onlyKeys(raw, ['measurement_result_id', 'result_status', 'measured_value'], 'in a measurement entry');
      const id = positiveInt(raw.measurement_result_id, 'measurement_result_id');
      if (typeof raw.result_status !== 'string' || !RESULT_STATUSES.includes(raw.result_status)) {
        throw new HttpError(422, 'INVALID_VALUE', `result_status must be one of ${RESULT_STATUSES.join(', ')}.`);
      }
      const status = raw.result_status as ResultStatus;
      const value = raw.measured_value;
      let measured: number | null = null;
      if (status === 'RECORDED') {
        // DECIMAL(10,3): at most 7 digits before and 3 after the decimal point.
        if (typeof value !== 'number' || !/^-?\d{1,7}(\.\d{1,3})?$/.test(String(value))) {
          throw new HttpError(422, 'INVALID_VALUE', 'A RECORDED measurement needs measured_value with at most 7 digits before and 3 after the decimal point.');
        }
        measured = value;
      } else if (value !== undefined && value !== null) {
        throw new HttpError(422, 'INVALID_VALUE', `measured_value must be absent or null when result_status is ${status}.`);
      }
      if (seen.has(id)) throw new HttpError(422, 'DUPLICATE_ENTRY', `measurement_result_id ${id} appears twice.`);
      seen.add(id);
      measurements.push({ measurement_result_id: id, result_status: status, measured_value: measured });
    }
  }

  if (cardStatus === null && checklist.length === 0 && measurements.length === 0) {
    throw new HttpError(422, 'EMPTY_EDIT', 'The request changes nothing.');
  }
  return { card_status: cardStatus, checklist, measurements };
}

export function validateCloseBody(body: unknown): Disposition {
  const obj = requireObject(body);
  onlyKeys(obj, ['disposition'], 'in the request');
  if (obj.disposition !== 'PASS' && obj.disposition !== 'REJECT') {
    throw new HttpError(422, 'INVALID_VALUE', "disposition must be 'PASS' or 'REJECT'.");
  }
  return obj.disposition;
}

export function validateOpenBody(body: unknown): string {
  const obj = requireObject(body);
  onlyKeys(obj, ['unit_serial'], 'in the request');
  const serial = obj.unit_serial;
  if (typeof serial !== 'string' || serial.length < 1 || serial.length > 40 || !/^[A-Za-z0-9._-]+$/.test(serial)) {
    throw new HttpError(422, 'INVALID_VALUE', 'unit_serial must be 1 to 40 characters: letters, digits, dot, underscore or hyphen.');
  }
  return serial;
}
