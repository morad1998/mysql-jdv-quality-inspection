import { createServer } from 'node:http';
import { createApp } from './app.ts';
import { loadConfig } from './config.ts';
import { createMySqlDb } from './db.ts';

const config = loadConfig();
const db = await createMySqlDb(config.db);
const server = createServer(createApp(db, (line) => console.log(line)));

server.listen(config.port, config.host, () => {
  console.log(`API listening on http://${config.host}:${config.port}/api (demo authentication only; do not expose it)`);
});

async function stop(): Promise<void> {
  server.close();
  await db.close();
  process.exit(0);
}
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
