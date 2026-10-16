import { createHash } from 'node:crypto';
import type { AppUser, ChecklistItem, Db, EditDoc, MeasurementItem, ReadDoc } from '../src/types.ts';

/**
 * An in-memory stand-in for the database, written for the route tests only.
 * It MODELS the behavior recorded in docs/evidence/day-2 (root written before children, ETag over the document,
 * the close rules, the final-card lock, the one-active-card rule). It proves the API's own logic, NOT that MySQL
 * behaves this way: test/integration.test.ts does that against the real database.
 */
interface FakeCard {
  id: number;
  unitId: number;
  status: string;
  disposition: string | null;
  openedBy: number;
  closedBy: number | null;
  closedAt: string | null;
  measurements: MeasurementItem[];
  checklist: ChecklistItem[];
  criticalOpen: boolean;
}

export function dbError(errno: number, text: string): Error {
  return Object.assign(new Error(text), { errno, sqlMessage: text });
}

const USERS: AppUser[] = [
  { user_id: 1, username: 'inspector1', role_code: 'INSPECTOR' },
  { user_id: 2, username: 'inspector2', role_code: 'INSPECTOR' },
  { user_id: 3, username: 'supervisor1', role_code: 'SUPERVISOR' },
];
const UNITS: Record<string, number> = { 'SN-DEMO-0001': 1, 'SN-DEMO-0002': 2, 'SN-DEMO-0003': 3 };
const hash = (kind: string, value: unknown): string => createHash('sha256').update(kind + JSON.stringify(value)).digest('hex').slice(0, 32);
const isFinal = (status: string): boolean => status === 'CLOSED' || status === 'REJECTED';

export class FakeDb implements Db {
  cards: FakeCard[] = [];
  nextCardId = 1;
  nextResultId = 1;
  writes = 0;

  constructor() {
    // card 1: a finished card on unit 1. card 2: an open card on unit 3 with three pending checklist items.
    this.add(1, 'CLOSED', 'PASS', 3, '2026-10-16 01:13:25.000000', true);
    this.add(3, 'OPEN', null, null, null, false);
  }

  add(unitId: number, status: string, disposition: string | null, closedBy: number | null, closedAt: string | null, answered: boolean): number {
    const id = this.nextCardId++;
    const mk = (): [MeasurementItem[], ChecklistItem[]] => {
      const m: MeasurementItem[] = [1, 2].map(() => ({
        measurement_result_id: this.nextResultId++,
        result_status: answered ? 'NOT_APPLICABLE' : 'PENDING',
        measured_value: null,
        recorded_by: answered ? 1 : null,
        recorded_at: answered ? '2026-10-16 01:13:25.000000' : null,
      }));
      const c: ChecklistItem[] = [1, 2, 3].map(() => ({
        checklist_result_id: this.nextResultId++,
        answer_code: answered ? 'YES' : 'PENDING',
        answered_by: answered ? 1 : null,
        answered_at: answered ? '2026-10-16 01:13:25.000000' : null,
      }));
      return [m, c];
    };
    const [measurements, checklist] = mk();
    this.cards.push({ id, unitId, status, disposition, openedBy: 1, closedBy, closedAt, measurements, checklist, criticalOpen: false });
    return id;
  }

  private card(id: number): FakeCard | undefined {
    return this.cards.find((c) => c.id === id);
  }

  private editOf(card: FakeCard): EditDoc {
    const content = {
      _id: card.id,
      card_status: card.status,
      disposition: card.disposition,
      closed_by: card.closedBy,
      closed_at: card.closedAt,
      measurements: structuredClone(card.measurements),
      checklist: structuredClone(card.checklist),
    };
    return { ...content, _metadata: { etag: hash('edit', content) } };
  }

  private readOf(card: FakeCard): ReadDoc {
    const serial = Object.keys(UNITS).find((k) => UNITS[k] === card.unitId) ?? 'SN-UNKNOWN';
    const content = {
      _id: card.id,
      card_status: card.status,
      disposition: card.disposition,
      opened_by: card.openedBy,
      opened_at: '2026-10-16 01:13:25.000000',
      closed_by: card.closedBy,
      closed_at: card.closedAt,
      unit: { unit_id: card.unitId, unit_serial: serial, work_order_id: 1 },
      measurements: structuredClone(card.measurements) as unknown[],
      checklist: structuredClone(card.checklist) as unknown[],
      findings: null,
      attachments: null,
    };
    return { ...content, _metadata: { etag: hash('read', content) } };
  }

  async findUser(username: string): Promise<AppUser | null> {
    return USERS.find((u) => u.username === username) ?? null;
  }
  async listCards(): Promise<ReadDoc[]> {
    return this.cards.map((c) => this.readOf(c));
  }
  async getReadDocument(cardId: number): Promise<ReadDoc | null> {
    const c = this.card(cardId);
    return c ? this.readOf(c) : null;
  }
  async getEditDocument(cardId: number): Promise<EditDoc | null> {
    const c = this.card(cardId);
    return c ? this.editOf(c) : null;
  }

  async writeEditDocument(cardId: number, doc: EditDoc): Promise<void> {
    const card = this.card(cardId);
    if (!card) return;
    this.writes++;
    const current = this.editOf(card);
    if (doc._metadata.etag !== current._metadata.etag) {
      throw dbError(6494, `Cannot update JSON duality view. The ETAG of the document in the database did not match the ETAG '"${doc._metadata.etag}"' passed in.`);
    }
    const rootChanged =
      doc.card_status !== card.status || doc.disposition !== card.disposition || doc.closed_by !== card.closedBy || doc.closed_at !== card.closedAt;
    // Atomic: work on copies and commit only when every part succeeded.
    const next = { status: card.status, disposition: card.disposition, closedBy: card.closedBy, closedAt: card.closedAt };
    if (rootChanged) {
      // The root is written FIRST, so the close rules see the OLD state of the children.
      if (isFinal(card.status)) throw dbError(50020, 'A closed or rejected card cannot be changed');
      if (doc.card_status === 'CLOSED') {
        if (doc.disposition === null) throw dbError(3819, "Check constraint 'chk_card_disposition_final' is violated.");
        if (card.checklist.some((c) => c.answer_code === 'PENDING')) throw dbError(50002, 'Cannot close card: unanswered checklist items exist');
        if (card.criticalOpen) throw dbError(50003, 'Cannot close card: an open CRITICAL finding exists');
      }
      next.status = doc.card_status;
      next.disposition = doc.disposition;
      next.closedBy = doc.closed_by;
      next.closedAt = doc.closed_at;
    }
    const measurements = structuredClone(card.measurements);
    const checklist = structuredClone(card.checklist);
    for (const item of doc.measurements ?? []) {
      const stored = measurements.find((m) => m.measurement_result_id === item.measurement_result_id);
      if (!stored) throw dbError(6489, `Path '$.measurements' is not mapped to any column of measurement_result.`);
      if (JSON.stringify(stored) !== JSON.stringify(item)) {
        if (isFinal(card.status)) throw dbError(50021, 'Measurement results of a closed or rejected card cannot be changed');
        Object.assign(stored, item);
      }
    }
    for (const item of doc.checklist ?? []) {
      const stored = checklist.find((c) => c.checklist_result_id === item.checklist_result_id);
      if (!stored) throw dbError(6489, `Path '$.checklist' is not mapped to any column of checklist_result.`);
      if (JSON.stringify(stored) !== JSON.stringify(item)) {
        if (isFinal(card.status)) throw dbError(50022, 'Checklist results of a closed or rejected card cannot be changed');
        Object.assign(stored, item);
      }
    }
    Object.assign(card, next, { measurements, checklist });
  }

  async openCard(unitSerial: string, openedBy: number): Promise<number | null> {
    const unitId = UNITS[unitSerial];
    if (unitId === undefined) return null;
    if (this.cards.some((c) => c.unitId === unitId && !isFinal(c.status))) {
      throw dbError(1062, "Duplicate entry '3' for key 'inspection_card.uq_card_one_active_per_unit'");
    }
    const id = this.add(unitId, 'OPEN', null, null, null, false);
    const card = this.card(id);
    if (card) card.openedBy = openedBy;
    return id;
  }

  async close(): Promise<void> {}
}
