// Prints the address to open for `pnpm run dev`. The browser's origin must match the
// BROWSER_REST_URL that ../.env gives the app (CORS), so the address is derived from it:
// https on Caddy after `./dev.sh https on` (pages proxied to this dev server), else the
// dev server's own port 3000 on SITE_DOMAIN.
import { readFileSync } from "node:fs";
import { parse } from "dotenv";

let env = {};
try {
  env = parse(readFileSync(new URL("../../.env", import.meta.url)));
} catch {
  // No generated .env yet: `./sb config generate` creates it.
}
const restUrl = env.BROWSER_REST_URL ?? "";
const domain = env.SITE_DOMAIN || "local.statbus.org";
const open = restUrl.startsWith("https://")
  ? `${restUrl}/`
  : `http://${domain}:3000/`;
console.log(
  `\n>>> Open the app at: ${open}\n` +
    `    (NOT localhost:3000: Next.js prints that below, but CORS will block /rest calls.)\n`
);
