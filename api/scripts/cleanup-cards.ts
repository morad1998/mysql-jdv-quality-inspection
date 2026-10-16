import mysql from 'mysql2/promise';
import type { ResultSetHeader } from 'mysql2/promise';
import { loadConfig } from '../src/config.ts';

/*
 * Deletes demo cards that were created through the API, directly in the database, children first.
 * Usage: npm run cleanup -- <card id> [<card id> ...]
 * Cards 1 and 2 are the verified baseline and are refused. Auto-increment counters are not reset.
 */
const ids = process.argv.slice(2).map((arg) => Number(arg));
if (ids.length === 0 || ids.some((n) => !Number.isInteger(n) || n < 3)) {
  console.error('Usage: npm run cleanup -- <card id> [<card id> ...]   (ids must be 3 or higher: cards 1 and 2 are the verified baseline)');
  process.exit(1);
}

const { db } = loadConfig();
const pool = mysql.createPool({ host: db.host, port: db.port, user: db.user, password: db.password, database: db.database });
try {
  for (const table of ['attachment_metadata', 'quality_finding', 'checklist_result', 'measurement_result']) {
    const [result] = await pool.query<ResultSetHeader>(`DELETE FROM ${table} WHERE card_id IN (?)`, [ids]);
    console.log(`${table}: ${result.affectedRows} row(s) deleted`);
  }
  const [cards] = await pool.query<ResultSetHeader>('DELETE FROM inspection_card WHERE card_id IN (?)', [ids]);
  console.log(`inspection_card: ${cards.affectedRows} row(s) deleted`);
} finally {
  await pool.end();
}
