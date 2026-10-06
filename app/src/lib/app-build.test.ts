import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseArtifactSHA } from "./running-identity";

const script = resolve(__dirname, "../../scripts/stamp-app-build.mjs");
const fixture = () => {
  const base = resolve(__dirname, "../../../tmp");
  mkdirSync(base, { recursive: true });
  const path = mkdtempSync(resolve(base, "452-c-stamp-"));
  mkdirSync(resolve(path, "public"));
  return path;
};
const readArtifact = (cwd: string) =>
  JSON.parse(readFileSync(resolve(cwd, "public/_statbus-build.json"), "utf8"));

test("image stamping preserves full SHA, independent of runtime target configuration", () => {
  const cwd = fixture();
  const source = "a".repeat(40);
  execFileSync(process.execPath, [script, "--image", source], {
    cwd,
    env: {
      ...process.env,
      COMMIT: "b".repeat(40),
      PUBLIC_STATBUS_VERSION: "target",
    },
  });
  expect(parseArtifactSHA(readArtifact(cwd))).toBe(source);
});

test("local builds overwrite stale artifacts with unknown even with configured full SHA", () => {
  const cwd = fixture();
  execFileSync(process.execPath, [script, "--image", "a".repeat(40)], { cwd });
  execFileSync(process.execPath, [script], {
    cwd,
    env: {
      ...process.env,
      COMMIT: "b".repeat(40),
      STATBUS_BUILD_COMMIT: "b".repeat(40),
    },
  });
  expect(readArtifact(cwd)).toEqual({ commit_sha: null });
});

test.each(["", "abcdef12", "a".repeat(40) + "-dirty", "g".repeat(40)])(
  "unproven image stamp %s remains unknown",
  (commit) => {
    const cwd = fixture();
    execFileSync(process.execPath, [script, "--image", commit], { cwd });
    expect(readArtifact(cwd)).toEqual({ commit_sha: null });
  }
);
