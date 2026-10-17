import { env } from "./env.js";

export async function storeFile(filename: string, bytes: Uint8Array, contentType: string) {
  const safe = filename.replace(/[^\w.\-]+/g, "-").slice(0, 80) || "file";
  const path = `${Date.now()}-${safe}`;
  const response = await fetch(`${env.supabaseUrl}/storage/v1/object/woolly/${path}`, {
    method: "POST",
    headers: {
      apikey: env.supabaseSecretKey,
      "content-type": contentType || "application/octet-stream",
      "x-upsert": "true",
    },
    body: Buffer.from(bytes),
  });
  if (!response.ok) {
    throw new Error(`Upload failed (${response.status}): ${await response.text()}`);
  }
  return {
    path,
    filename: safe,
    url: `${env.supabaseUrl}/storage/v1/object/public/woolly/${path}`,
  };
}
