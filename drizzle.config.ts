import { defineConfig } from "drizzle-kit";
import { config } from "dotenv";

config({ path: ".env.local" });

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/server/db/schema",
  out: "./src/server/db/schema",
  dbCredentials: {
    url: process.env.DATABASE_URL!,
  },
});