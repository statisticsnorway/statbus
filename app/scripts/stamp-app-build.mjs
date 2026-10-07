// Stamp the local artifact identity into public/_statbus-build.json.
//
// Precedence:
//   --image <40-hex>  -> { "commit_sha": "<40-hex>", "dirty": false }  (image
//                        publication proves the checkout; wins over local state)
//   --image <invalid> -> { "commit_sha": null }                        (unproven)
//   no --image        -> { "commit_sha": "<HEAD>", "dirty": true|false } (local)
//   no git work tree  -> { "commit_sha": null }                        (unknown)
//
// `dirty` is decided by `git status --porcelain -- .` from this directory:
// untracked files count, so a local artifact is never labelled with a bare HEAD
// while the tree it was built from has uncommitted work. Images always use the
// checkout SHA (--image), so a dev-written stamp can never describe a release.
//
// The content computation is shared with scripts/watch-app-build.mjs, which
// keeps the local stamp fresh while `pnpm run dev` is running.
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { pathToFileURL } from "node:url";

export const STAMP_RELATIVE_PATH = "public/_statbus-build.json";

const HEX40 = /^[0-9a-f]{40}$/;

function git(args, cwd) {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

/**
 * Compute the artifact identity for a checkout.
 *
 * @param {{ image?: string | null, cwd?: string }} [options]
 *   `image`: the value of `--image`; pass `undefined` when the flag is absent
 *   so the local fallback applies. `null` means the flag was present without a
 *   (valid) value, which stays unknown.
 * @returns {{ commit_sha: string | null, dirty?: boolean }}
 */
export function computeStampContent({ image, cwd = process.cwd() } = {}) {
  if (image !== undefined) {
    return { commit_sha: typeof image === "string" && HEX40.test(image) ? image : null };
  }

  let head;
  try {
    head = git(["rev-parse", "HEAD"], cwd);
  } catch {
    // Docker build, tarball extract, or any other context without a work tree.
    return { commit_sha: null };
  }
  if (!HEX40.test(head)) return { commit_sha: null };

  let dirty = false;
  try {
    dirty = git(["status", "--porcelain", "--", "."], cwd).length > 0;
  } catch {
    dirty = false;
  }

  return { commit_sha: head, dirty };
}

export function writeStamp(content, { cwd = process.cwd() } = {}) {
  const path = `${cwd}/${STAMP_RELATIVE_PATH}`;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(content) + "\n");
}

function main() {
  const hasImage = process.argv[2] === "--image";
  const image = hasImage ? (process.argv[3] ?? null) : undefined;
  writeStamp(computeStampContent({ image }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
