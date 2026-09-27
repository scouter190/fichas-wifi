import { config } from "dotenv";
config({ path: ".env.local" });

import { conComercio } from "./clients";
import { sql } from "drizzle-orm";

async function main() {
  const ACME = "e9cdab6a-a2a4-415e-92b2-0a6badda8ed3";

  const resultado = await conComercio(ACME, async (tx) => {
    return tx.execute(sql`SELECT codigo FROM ficha`);
  });

  console.log(resultado.rows);
}

main();