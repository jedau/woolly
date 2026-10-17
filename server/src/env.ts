import { config } from "dotenv";
import { resolve } from "node:path";

config({ path: resolve(import.meta.dirname, "../../.env") });

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing ${name} in .env`);
  }
  return value;
}

export const env = {
  geminiApiKey: required("GEMINI_API_KEY"),
  geminiModel: process.env.GEMINI_MODEL?.trim() || "gemma-4-26b-a4b-it",
  databaseUrl: required("DATABASE_URL"),
  supabaseUrl: required("SUPABASE_URL").replace(/\/$/, ""),
  supabaseSecretKey: required("SUPABASE_SERVICE_ROLE_KEY"),
  port: Number(process.env.PORT || 8787),
};

process.env.GOOGLE_GENERATIVE_AI_API_KEY = env.geminiApiKey;
