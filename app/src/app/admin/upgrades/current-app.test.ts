import { currentAppRow, newerThanCurrentApp } from "./current-app";

const source = {
  commit_sha: "a".repeat(40),
  committed_at: "2026-01-01T00:00:00Z",
};
const target = {
  commit_sha: "b".repeat(40),
  committed_at: "2026-02-01T00:00:00Z",
};

test("current artifact row is resolved separately even outside 100-row history", () => {
  const history = Array.from({ length: 101 }, (_, i) => ({
    ...target,
    commit_sha: i.toString(16).padStart(40, "0"),
  })).slice(0, 100);
  expect(history.some((row) => row.commit_sha === source.commit_sha)).toBe(
    false
  );
  const current = currentAppRow(source.commit_sha, [source]);
  expect(current).toEqual(source);
  expect(newerThanCurrentApp(target, current)).toBe(true);
});

test("restored source app, not target program or newest history, anchors comparisons", () => {
  expect(
    newerThanCurrentApp(source, currentAppRow(source.commit_sha, [source]))
  ).toBe(false);
  expect(
    newerThanCurrentApp(target, currentAppRow(source.commit_sha, [source]))
  ).toBe(true);
  expect(
    newerThanCurrentApp(source, currentAppRow(target.commit_sha, [target]))
  ).toBe(false);
});

test("unknown, pruned, mismatched and ambiguous baselines cannot supply restore evidence", () => {
  for (const current of [
    currentAppRow(null, [source]),
    currentAppRow(source.commit_sha, []),
    currentAppRow(source.commit_sha, [target]),
    currentAppRow(source.commit_sha, [source, source]),
    currentAppRow(source.commit_sha, [{ ...source, committed_at: "invalid" }]),
  ]) {
    expect(current).toBeNull();
    expect(newerThanCurrentApp(target, current)).toBe(false);
  }
});
