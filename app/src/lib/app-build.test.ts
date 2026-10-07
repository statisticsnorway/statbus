import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArtifactSHA } from "./running-identity";

const script = resolve(__dirname, "../../scripts/stamp-app-build.mjs");
const watcher = resolve(__dirname, "../../scripts/watch-app-build.mjs");

const git = (cwd: string, ...args: string[]) =>
  execFileSync("git", args, { cwd, encoding: "utf8" }).trim();

// A scratch git work tree with public/ and the same ignore rule as app/ so the
// generated stamp never makes itself dirty.
const gitFixture = () => {
  const base = resolve(__dirname, "../../../tmp");
  mkdirSync(base, { recursive: true });
  const path = mkdtempSync(resolve(base, "457-stamp-"));
  mkdirSync(resolve(path, "public"));
  writeFileSync(resolve(path, ".gitignore"), "public/_statbus-build.json\n");
  git(path, "init", "-q");
  git(path, "config", "user.email", "test@example.com");
  git(path, "config", "user.name", "test");
  writeFileSync(resolve(path, "README.md"), "seed\n");
  git(path, "add", "-A");
  git(path, "commit", "-q", "-m", "init");
  return path;
};

// A directory outside any git work tree (macOS/OS temp root is not a repo).
const nonGitFixture = () => {
  const path = mkdtempSync(resolve(tmpdir(), "457-nongit-"));
  mkdirSync(resolve(path, "public"));
  return path;
};

const stamp = (cwd: string) =>
  execFileSync(process.execPath, [script], { cwd, encoding: "utf8" });

const readArtifact = (cwd: string) =>
  JSON.parse(readFileSync(resolve(cwd, "public/_statbus-build.json"), "utf8"));

test("clean work tree stamps HEAD with dirty=false", () => {
  const cwd = gitFixture();
  stamp(cwd);
  expect(readArtifact(cwd)).toEqual({
    commit_sha: git(cwd, "rev-parse", "HEAD"),
    dirty: false,
  });
});

test("dirty tracked change sets the dirty flag", () => {
  const cwd = gitFixture();
  writeFileSync(resolve(cwd, "README.md"), "modified\n");
  stamp(cwd);
  expect(readArtifact(cwd)).toEqual({
    commit_sha: git(cwd, "rev-parse", "HEAD"),
    dirty: true,
  });
});

test("an untracked file alone sets the dirty flag", () => {
  const cwd = gitFixture();
  writeFileSync(resolve(cwd, "new-untracked.txt"), "x\n");
  stamp(cwd);
  expect(readArtifact(cwd)).toEqual({
    commit_sha: git(cwd, "rev-parse", "HEAD"),
    dirty: true,
  });
});

test("image SHA wins over local state and is stamped verbatim", () => {
  const cwd = gitFixture();
  writeFileSync(resolve(cwd, "README.md"), "dirty\n");
  const source = "a".repeat(40);
  execFileSync(process.execPath, [script, "--image", source], {
    cwd,
    env: { ...process.env, COMMIT: "b".repeat(40) },
  });
  expect(parseArtifactSHA(readArtifact(cwd))).toBe(source);
  expect(readArtifact(cwd)).toEqual({ commit_sha: source });
});

test("invalid or missing --image stays unknown and does not fall back to local", () => {
  const cwd = gitFixture();
  for (const commit of [
    "",
    "abcdef12",
    `${"a".repeat(40)}-dirty`,
    "g".repeat(40),
  ]) {
    execFileSync(process.execPath, [script, "--image", commit], { cwd });
    expect(readArtifact(cwd)).toEqual({ commit_sha: null });
  }
  execFileSync(process.execPath, [script, "--image"], { cwd });
  expect(readArtifact(cwd)).toEqual({ commit_sha: null });
});

test("outside a git work tree the stamp is unknown and the script exits 0", () => {
  const cwd = nonGitFixture();
  expect(() => stamp(cwd)).not.toThrow();
  expect(readArtifact(cwd)).toEqual({ commit_sha: null });
});

test("the one-shot output equals the watcher's computed content", () => {
  const cwd = gitFixture();
  writeFileSync(resolve(cwd, "README.md"), "changed\n");
  const code = [
    `const m = await import(${JSON.stringify(pathToFileURL(watcher).href)});`,
    "process.stdout.write(",
    "  JSON.stringify(m.computeStampContent({ cwd: process.cwd() }))",
    ");",
  ].join("\n");
  const watcherContent = JSON.parse(
    execFileSync(process.execPath, ["--input-type=module", "-e", code], {
      cwd,
      encoding: "utf8",
    })
  );
  stamp(cwd);
  expect(readArtifact(cwd)).toEqual(watcherContent);
  expect(watcherContent).toEqual({
    commit_sha: git(cwd, "rev-parse", "HEAD"),
    dirty: true,
  });
});
