import { drizzle } from "drizzle-orm/node-postgres";
import { sql } from "drizzle-orm";
import { Pool } from "pg";
import * as schema from "./schema/schema";

let _db: ReturnType<typeof drizzle<typeof schema, Pool>> | undefined;

function getDb() {
  if (!_db) {
    const pool = new Pool({ connectionString: process.env.DATABASE_URL });
    _db = drizzle(pool, { schema });
  }
  return _db;
}

type Tx = Parameters<Parameters<ReturnType<typeof getDb>["transaction"]>[0]>[0];

export async function conComercio<T>(
  comercioId: string,
  fn: (tx: Tx) => Promise<T>
): Promise<T> {
  return getDb().transaction(async (tx) => {
    await tx.execute(
      sql`SELECT set_config('app.comercio_id', ${comercioId}, true)`
    );
    return fn(tx);
  });
}