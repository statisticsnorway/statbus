// `pnpm run dev`: starts this checkout's Next.js dev server on its slot's port
// (APP_DEV_PORT in ../.env, slot offset+7, STATBUS-623) and prints the address to
// open. The browser's origin must match the BROWSER_REST_URL that ../.env gives
// the app (CORS): https on the slot's Caddy after `./dev.sh https on` (HTTP/2,
// pages proxied to this dev server), else this dev server's own port on
// SITE_DOMAIN. Without a generated .env it falls back to port 3000.
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { parse } from "dotenv";

let env = {};
try {
  env = parse(readFileSync(new URL("../../.env", import.meta.url)));
} catch {
  // No generated .env yet: `./sb config generate` creates it.
}
const port = env.APP_DEV_PORT || "3000";
const restUrl = env.BROWSER_REST_URL ?? "";
const domain = env.SITE_DOMAIN || "local.statbus.org";
const open = restUrl.startsWith("https://") ? `${restUrl}/` : `http://${domain}:${port}/`;
console.log(
  `\n>>> Open the app at: ${open}\n` +
    `    (NOT localhost:${port}: Next.js prints that below, but CORS will block /rest calls.)\n`
);

const run = (cmd, args) => spawn(cmd, args, { stdio: "inherit", shell: process.platform === "win32" });
const watcher = run("node", ["scripts/watch-app-build.mjs"]);
const next = run("next", ["dev", "--turbopack", "-p", port, ...process.argv.slice(2)]);
const stop = (code) => {
  watcher.kill();
  process.exit(code ?? 0);
};
next.on("exit", stop);
process.on("SIGINT", () => next.kill("SIGINT"));
process.on("SIGTERM", () => next.kill("SIGTERM"));
