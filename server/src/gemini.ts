import { env } from "./env.js";

type GeminiPart = { text: string };

export async function geminiText(prompt: string): Promise<string> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${env.geminiModel}:generateContent`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": env.geminiApiKey,
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] satisfies GeminiPart[] }],
        generationConfig: { temperature: 0.4 },
      }),
    },
  );
  const body = await response.json();
  if (!response.ok) {
    throw new Error(body?.error?.message || `Gemma request failed (${response.status})`);
  }
  const text = body?.candidates?.[0]?.content?.parts?.map((part: GeminiPart) => part.text).join("\n");
  if (!text) throw new Error("Gemma returned an empty response");
  return text;
}

export async function embedText(text: string): Promise<number[] | null> {
  const response = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": env.geminiApiKey,
      },
      body: JSON.stringify({
        content: { parts: [{ text: text.slice(0, 8000) }] },
        outputDimensionality: 768,
      }),
    },
  );
  if (!response.ok) return null;
  const body = await response.json();
  const values = body?.embedding?.values;
  return Array.isArray(values) ? values : null;
}

export function parseJson<T>(text: string): T {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const raw = fenced?.[1] ?? text;
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error("Model response did not contain JSON");
  return JSON.parse(raw.slice(start, end + 1)) as T;
}
