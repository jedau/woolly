import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { env } from "./env.js";
import { sql } from "./db.js";

const schema = readFileSync(resolve(import.meta.dirname, "schema.sql"), "utf8");

await sql.unsafe(schema);
await ensureBucket();
console.log("Database schema is ready.");
await sql.end();

async function ensureBucket() {
  const response = await fetch(`${env.supabaseUrl}/storage/v1/bucket`, {
    method: "POST",
    headers: {
      apikey: env.supabaseSecretKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({ id: "woolly", name: "woolly", public: true }),
  });
  if (response.ok || response.status === 409) return;
  const body = await response.text();
  if (body.toLowerCase().includes("already exists")) return;
  throw new Error(`Could not create storage bucket (${response.status}): ${body}`);
}
