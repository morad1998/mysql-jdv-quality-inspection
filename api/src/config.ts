export interface Config {
  host: string;
  port: number;
  db: { host: string; port: number; user: string; password: string; database: string };
}

/** Reads the same variable names as the repository's .env.example. Nothing is logged. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const need = (key: string): string => {
    const value = env[key];
    if (!value) throw new Error(`Missing environment variable ${key} (copy it from .env.example into .env)`);
    return value;
  };
  return {
    host: env.API_HOST ?? '127.0.0.1',
    port: Number(env.API_PORT ?? '3000'),
    db: {
      host: env.MYSQL_HOST ?? '127.0.0.1',
      port: Number(env.MYSQL_PORT ?? '3307'),
      user: need('MYSQL_USER'),
      password: need('MYSQL_PASSWORD'),
      database: need('MYSQL_DATABASE'),
    },
  };
}
