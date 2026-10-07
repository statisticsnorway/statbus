#!/usr/bin/env node
// Dev-only watcher: keep public/_statbus-build.json in step with HEAD + dirty
// while `pnpm run dev` runs. Started by `pnpm run dev` next to `next dev`; it
// must never be imported by any file under app/src (it would drag `git` into
// the bundle).
//
// It stamps once at start, then polls HEAD and `git status --porcelain -- .`
// every POLL_MS, writing only when the content changes and printing one line
// when it does. SIGINT/SIGTERM (from the dev server) make it exit cleanly.
import { pathToFileURL } from "node:url";
import { computeStampContent, writeStamp } from "./stamp-app-build.mjs";

export { computeStampContent };

const POLL_MS = 5000;

function formatLine(content) {
  if (!content.commit_sha) return "stamp: unknown";
  const short = content.commit_sha.slice(0, 8);
  return `stamp: ${short}${content.dirty ? " (+dirty)" : ""}`;
}

function main() {
  const cwd = process.cwd();
  let current = null;

  const stamp = (force) => {
    const content = computeStampContent({ cwd });
    const serialized = JSON.stringify(content) + "\n";
    if (!force && serialized === current) return;
    writeStamp(content, { cwd });
    current = serialized;
    console.log(formatLine(content));
  };

  stamp(true);
  const timer = setInterval(() => stamp(false), POLL_MS);

  const shutdown = () => {
    clearInterval(timer);
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
