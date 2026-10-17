import postgres from "postgres";
import { env } from "./env.js";

const url = new URL(env.databaseUrl);
const directHost = url.hostname;
const projectRef = directHost.match(/^db\.([a-z0-9]+)\.supabase\.co$/)?.[1];

// Free Supabase direct hosts are IPv6-only. This network cannot reach them,
// so the session pooler (IPv4) is used for db.<ref>.supabase.co.
const host = projectRef ? "aws-0-ap-south-1.pooler.supabase.com" : directHost;
const username = projectRef
  ? `postgres.${projectRef}`
  : decodeURIComponent(url.username);
const port = projectRef ? 5432 : Number(url.port || 5432);

export const sql = postgres({
  host,
  port,
  user: username,
  pass: decodeURIComponent(url.password),
  database: url.pathname.replace(/^\//, "") || "postgres",
  ssl: "require",
  max: 5,
});

export const clientId = "11111111-1111-4111-8111-111111111111";
export const workerId = "22222222-2222-4222-8222-222222222222";
