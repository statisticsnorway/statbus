export interface RunningIdentity {
  commit_sha: string;
  resolved_name: string;
  release_status: "commit" | "prerelease" | "release";
  build_name: string | null;
}

export interface RunningVersionDisplay {
  name: string;
  commit: string | null;
}

export function parseRunningIdentity(payload: unknown): RunningIdentity | null {
  if (!Array.isArray(payload) || payload.length !== 1) {
    return null;
  }

  const row: unknown = payload[0];
  if (
    typeof row !== "object" ||
    row === null ||
    !("commit_sha" in row) ||
    !("resolved_name" in row) ||
    !("release_status" in row) ||
    !("build_name" in row)
  ) {
    return null;
  }

  const candidate = row as Record<string, unknown>;
  if (
    typeof candidate.commit_sha !== "string" ||
    typeof candidate.resolved_name !== "string" ||
    !["commit", "prerelease", "release"].includes(
      String(candidate.release_status)
    ) ||
    (candidate.build_name !== null && typeof candidate.build_name !== "string")
  ) {
    return null;
  }

  return candidate as unknown as RunningIdentity;
}

function displayCommit(commit: string): string | null {
  if (!commit || commit === "unknown") {
    return null;
  }
  return commit.slice(0, 8);
}

export function runningVersionDisplay(
  runningIdentity: RunningIdentity | null,
  fallbackName: string,
  fallbackCommit: string
): RunningVersionDisplay {
  if (runningIdentity) {
    return {
      name: runningIdentity.resolved_name,
      commit: displayCommit(runningIdentity.commit_sha),
    };
  }

  return {
    name: fallbackName,
    commit: displayCommit(fallbackCommit),
  };
}
