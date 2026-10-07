// Hermetic tests for scripts/stamp-app-build.mjs and scripts/watch-app-build.mjs.
//
// STATBUS-457 (CI follow-up): the app CI image has NO `git` binary, so these
// tests must never shell out to a real one. Instead a scripted fake `git` is put
// first on the child PATH and driven from env vars; the real scripts under test
// are always the ones being run. The fake appends every invocation to a log so a
// test can prove the fake answered (and, for `--image`, that git was skipped
// entirely). Nothing here needs a real repository or a real git binary.
import { execFileSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArtifactSHA } from "./running-identity";

const script = resolve(__dirname, "../../scripts/stamp-app-build.mjs");
const watcher = resolve(__dirname, "../../scripts/watch-app-build.mjs");

const HEAD_CLEAN = "1".repeat(40);
const HEAD_OTHER = "2".repeat(40);

// A fake `git` that answers exactly the two invocations stamp-app-build.mjs
// makes. Every state field is passed explicitly by fakeGitEnv() so the script
// needs no shell defaulting: FAKE_GIT_HEAD empty => `rev-parse` exits 128 (no
// work tree); FAKE_GIT_STATUS is the verbatim `status --porcelain -- .` output;
// FAKE_GIT_STATUS_EXIT is its exit code. `$*` is appended to FAKE_GIT_LOG.
const FAKE_GIT = `#!/bin/sh
printf '%s\\n' "$*" >>"$FAKE_GIT_LOG"
case "$1" in
  rev-parse)
    if [ -z "$FAKE_GIT_HEAD" ]; then exit 128; fi
    printf '%s\\n' "$FAKE_GIT_HEAD"
    ;;
  status)
    printf '%s' "$FAKE_GIT_STATUS"
    exit "$FAKE_GIT_STATUS_EXIT"
    ;;
  *)
    exit 99
    ;;
esac
`;

const fakeRoot = mkdtempSync(resolve(tmpdir(), "457-hermetic-"));
const fakeBin = resolve(fakeRoot, "bin");
mkdirSync(fakeBin, { recursive: true });
const fakeGit = resolve(fakeBin, "git");
writeFileSync(fakeGit, FAKE_GIT);
chmodSync(fakeGit, 0o755);

// A directory that deliberately contains no `git` at all: PATH = only this.
const noGitBin = resolve(fakeRoot, "empty-bin");
mkdirSync(noGitBin, { recursive: true });

interface FakeGitState {
  /** Value of `rev-parse HEAD`; omit/empty to make rev-parse fail (no work tree). */
  head?: string;
  /** Verbatim output of `status --porcelain -- .`; empty means clean. */
  status?: string;
  /** Exit code of `status`; non-zero makes execFileSync throw. */
  statusExit?: number;
}

function fixture(label: string): string {
  const path = mkdtempSync(resolve(tmpdir(), `457-${label}-`));
  mkdirSync(resolve(path, "public"), { recursive: true });
  return path;
}

/** An env whose PATH reaches only the fake git, logging into `cwd/fake-git.log`. */
function fakeGitEnv(cwd: string, state: FakeGitState = {}) {
  const logPath = resolve(cwd, "fake-git.log");
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    PATH: `${fakeBin}${delimiter}${process.env.PATH ?? ""}`,
    FAKE_GIT_LOG: logPath,
    FAKE_GIT_HEAD: state.head ?? "",
    FAKE_GIT_STATUS: state.status ?? "",
    FAKE_GIT_STATUS_EXIT: String(state.statusExit ?? 0),
  };
  return { env, logPath };
}

/** Run the real script under the fake git; return its log. */
function runScript(cwd: string, args: string[] = [], state: FakeGitState = {}) {
  const { env, logPath } = fakeGitEnv(cwd, state);
  const stdout = execFileSync(process.execPath, [script, ...args], {
    cwd,
    env,
    encoding: "utf8",
  });
  return { stdout, logPath };
}

/** Every argument line the fake git recorded, in order. */
const gitLog = (logPath: string): string[] =>
  existsSync(logPath)
    ? readFileSync(logPath, "utf8")
        .split("\n")
        .filter((line) => line.length > 0)
    : [];

const readArtifact = (cwd: string) =>
  JSON.parse(readFileSync(resolve(cwd, "public/_statbus-build.json"), "utf8"));

test("clean work tree stamps HEAD with dirty=false", () => {
  const cwd = fixture("clean");
  const { logPath } = runScript(cwd, [], { head: HEAD_CLEAN });
  expect(readArtifact(cwd)).toEqual({ commit_sha: HEAD_CLEAN, dirty: false });
  // The fake — not a real git — answered, and only these two invocations.
  expect(gitLog(logPath)).toEqual([
    "rev-parse HEAD",
    "status --porcelain -- .",
  ]);
});

test("dirty tracked change sets the dirty flag", () => {
  const cwd = fixture("dirty-tracked");
  const { logPath } = runScript(cwd, [], {
    head: HEAD_CLEAN,
    status: " M README.md",
  });
  expect(readArtifact(cwd)).toEqual({ commit_sha: HEAD_CLEAN, dirty: true });
  expect(gitLog(logPath)).toEqual([
    "rev-parse HEAD",
    "status --porcelain -- .",
  ]);
});

test("an untracked file alone sets the dirty flag", () => {
  const cwd = fixture("dirty-untracked");
  const { logPath } = runScript(cwd, [], {
    head: HEAD_CLEAN,
    status: "?? scratch.txt",
  });
  expect(readArtifact(cwd)).toEqual({ commit_sha: HEAD_CLEAN, dirty: true });
  expect(gitLog(logPath)).toContain("status --porcelain -- .");
});

test("a failing git status does not fabricate dirtiness", () => {
  const cwd = fixture("status-fails");
  runScript(cwd, [], {
    head: HEAD_CLEAN,
    status: " M README.md",
    statusExit: 1,
  });
  expect(readArtifact(cwd)).toEqual({ commit_sha: HEAD_CLEAN, dirty: false });
});

test("a rev-parse output that is not a commit sha stays unknown", () => {
  const cwd = fixture("bad-head");
  const { logPath } = runScript(cwd, [], { head: "HEAD" });
  expect(readArtifact(cwd)).toEqual({ commit_sha: null });
  // A bad HEAD short-circuits before the status probe.
  expect(gitLog(logPath)).toEqual(["rev-parse HEAD"]);
});

test("a git that refuses rev-parse (no work tree) is unknown and exits 0", () => {
  const cwd = fixture("no-tree");
  const { logPath } = runScript(cwd, [], {});
  expect(readArtifact(cwd)).toEqual({ commit_sha: null });
  expect(gitLog(logPath)).toEqual(["rev-parse HEAD"]);
});

test("no git binary on PATH at all is unknown and exits 0", () => {
  const cwd = fixture("no-git-binary");
  const logPath = resolve(cwd, "fake-git.log");
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    PATH: noGitBin,
    FAKE_GIT_LOG: logPath,
  };
  expect(() =>
    execFileSync(process.execPath, [script], { cwd, env, encoding: "utf8" })
  ).not.toThrow();
  expect(readArtifact(cwd)).toEqual({ commit_sha: null });
  // Nothing was executed: there is no git to execute.
  expect(existsSync(logPath)).toBe(false);
});

test("--image wins over local git state and is stamped verbatim", () => {
  const cwd = fixture("image");
  const source = "a".repeat(40);
  const { logPath } = runScript(cwd, ["--image", source], {
    head: HEAD_CLEAN,
    status: " M README.md",
  });
  expect(readArtifact(cwd)).toEqual({ commit_sha: source });
  expect(parseArtifactSHA(readArtifact(cwd))).toBe(source);
  // Publication proves the checkout: git was never consulted.
  expect(gitLog(logPath)).toEqual([]);
});

test("invalid or missing --image stays unknown and does not fall back to local", () => {
  const cwd = fixture("image-invalid");
  const state: FakeGitState = { head: HEAD_CLEAN, status: " M README.md" };
  for (const value of [
    "",
    "abcdef12",
    `${"a".repeat(40)}-dirty`,
    "g".repeat(40),
  ]) {
    runScript(cwd, ["--image", value], state);
    expect(readArtifact(cwd)).toEqual({ commit_sha: null });
  }
  runScript(cwd, ["--image"], state);
  expect(readArtifact(cwd)).toEqual({ commit_sha: null });
  expect(gitLog(resolve(cwd, "fake-git.log"))).toEqual([]);
});

test("the one-shot output equals the watcher's computed content", () => {
  const cwd = fixture("watcher");
  const state: FakeGitState = { head: HEAD_OTHER, status: "?? scratch.txt" };
  const { env, logPath } = fakeGitEnv(cwd, state);
  const code = [
    `const m = await import(${JSON.stringify(pathToFileURL(watcher).href)});`,
    "process.stdout.write(",
    "  JSON.stringify(m.computeStampContent({ cwd: process.cwd() }))",
    ");",
  ].join("\n");
  const watcherContent = JSON.parse(
    execFileSync(process.execPath, ["--input-type=module", "-e", code], {
      cwd,
      env,
      encoding: "utf8",
    })
  );
  expect(gitLog(logPath)).toContain("rev-parse HEAD");

  execFileSync(process.execPath, [script], { cwd, env, encoding: "utf8" });
  expect(watcherContent).toEqual({ commit_sha: HEAD_OTHER, dirty: true });
  expect(readArtifact(cwd)).toEqual(watcherContent);
});
