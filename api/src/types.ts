export type Role = 'INSPECTOR' | 'SUPERVISOR';

export interface AppUser {
  user_id: number;
  username: string;
  role_code: Role;
}

export interface Metadata {
  etag: string;
}

export interface MeasurementItem {
  measurement_result_id: number;
  result_status: string;
  measured_value: number | null;
  recorded_by: number | null;
  recorded_at: string | null;
}

export interface ChecklistItem {
  checklist_result_id: number;
  answer_code: string;
  answered_by: number | null;
  answered_at: string | null;
}

/** The document served and accepted by the update-enabled view inspection_card_edit_dv. */
export interface EditDoc {
  _id: number;
  _metadata: Metadata;
  card_status: string;
  disposition: string | null;
  closed_by: number | null;
  closed_at: string | null;
  measurements: MeasurementItem[] | null;
  checklist: ChecklistItem[] | null;
}

/** The document served by the read-only view inspection_card_dv. */
export interface ReadDoc {
  _id: number;
  _metadata: Metadata;
  card_status: string;
  disposition: string | null;
  opened_by: number;
  opened_at: string;
  closed_by: number | null;
  closed_at: string | null;
  unit: { unit_id: number; unit_serial: string; work_order_id: number };
  measurements: unknown[] | null;
  checklist: unknown[] | null;
  findings: unknown[] | null;
  attachments: unknown[] | null;
}

export interface CardSummary {
  card_id: number;
  card_status: string;
  disposition: string | null;
  unit_serial: string;
}

export type AnswerCode = 'PENDING' | 'YES' | 'NO' | 'NOT_APPLICABLE';
export type ResultStatus = 'PENDING' | 'RECORDED' | 'NOT_APPLICABLE';

export interface ChecklistEdit {
  checklist_result_id: number;
  answer_code: AnswerCode;
}

export interface MeasurementEdit {
  measurement_result_id: number;
  result_status: ResultStatus;
  measured_value: number | null;
}

export interface EditRequest {
  card_status: 'IN_PROGRESS' | null;
  checklist: ChecklistEdit[];
  measurements: MeasurementEdit[];
}

export type Disposition = 'PASS' | 'REJECT';

/** Everything the API needs from the database. The real implementation is in db.ts. */
export interface Db {
  findUser(username: string): Promise<AppUser | null>;
  listCards(): Promise<ReadDoc[]>;
  getReadDocument(cardId: number): Promise<ReadDoc | null>;
  getEditDocument(cardId: number): Promise<EditDoc | null>;
  /** Writes a whole edit document through the update-enabled view. Throws the database error unchanged. */
  writeEditDocument(cardId: number, doc: EditDoc): Promise<void>;
  /** Plain INSERT into inspection_card. Returns the new card id, or null if the unit serial is unknown. */
  openCard(unitSerial: string, openedBy: number): Promise<number | null>;
  close(): Promise<void>;
}
