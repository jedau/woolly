import { serve } from "@hono/node-server";
import { app } from "./routes.js";
import { env } from "./env.js";

serve({ fetch: app.fetch, port: env.port }, () => {
  console.log(`Woolly API listening on http://localhost:${env.port}`);
});
