import mysql from 'mysql2/promise';
import type { Pool, ResultSetHeader, RowDataPacket } from 'mysql2/promise';
import type { Config } from './config.ts';
import type { AppUser, Db, EditDoc, ReadDoc } from './types.ts';

/** mysql2 returns JSON columns as objects; a string is parsed in case a driver setting returns text. */
function parseJson<T>(value: unknown): T {
  return (typeof value === 'string' ? JSON.parse(value) : value) as T;
}

export async function createMySqlDb(cfg: Config['db']): Promise<Db> {
  const pool: Pool = mysql.createPool({
    host: cfg.host,
    port: cfg.port,
    user: cfg.user,
    password: cfg.password,
    database: cfg.database,
    waitForConnections: true,
    connectionLimit: 5,
    dateStrings: true,
  });
  // Every statement below uses pool.query (the text protocol, values escaped by the driver), the same way the SQL scripts
  // in database/02_duality_views were run. Prepared statements (pool.execute) against Duality Views were not tested.
  // Writing a document built by the API with CAST(? AS JSON) is also new: D2 wrote documents built with JSON_SET.
  await pool.query('SELECT 1'); // fail fast: wrong port, password or plugin shows up here, not on the first request

  async function document<T>(view: string, cardId: number): Promise<T | null> {
    // The view and column names are fixed constants in this file, never user input; the id is a bound parameter.
    const [rows] = await pool.query<RowDataPacket[]>(`SELECT data FROM ${view} WHERE data->>'$._id' = ?`, [String(cardId)]);
    const row = rows[0];
    return row ? parseJson<T>(row.data) : null;
  }

  return {
    async findUser(username: string): Promise<AppUser | null> {
      const [rows] = await pool.query<RowDataPacket[]>(
        'SELECT user_id, username, role_code FROM app_user WHERE username = ? AND is_active = 1',
        [username],
      );
      const row = rows[0];
      return row ? { user_id: Number(row.user_id), username: String(row.username), role_code: row.role_code } : null;
    },

    async listCards(): Promise<ReadDoc[]> {
      const [rows] = await pool.query<RowDataPacket[]>(
        "SELECT data FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED)",
      );
      return rows.map((row) => parseJson<ReadDoc>(row.data));
    },

    getReadDocument: (cardId: number) => document<ReadDoc>('inspection_card_dv', cardId),
    getEditDocument: (cardId: number) => document<EditDoc>('inspection_card_edit_dv', cardId),

    async writeEditDocument(cardId: number, doc: EditDoc): Promise<void> {
      // One UPDATE through the view is atomic: MySQL runs the root and child sub-statements as one operation (D-024).
      await pool.query(`UPDATE inspection_card_edit_dv SET data = CAST(? AS JSON) WHERE data->>'$._id' = ?`, [
        JSON.stringify(doc),
        String(cardId),
      ]);
    },

    async openCard(unitSerial: string, openedBy: number): Promise<number | null> {
      const [units] = await pool.query<RowDataPacket[]>('SELECT unit_id FROM production_unit WHERE unit_serial = ?', [unitSerial]);
      const unit = units[0];
      if (!unit) return null;
      // A plain INSERT: the views cannot insert. The trigger creates the PENDING result rows (N2).
      const [result] = await pool.query<ResultSetHeader>('INSERT INTO inspection_card (unit_id, opened_by) VALUES (?, ?)', [
        unit.unit_id,
        openedBy,
      ]);
      return result.insertId;
    },

    async close(): Promise<void> {
      await pool.end();
    },
  };
}
