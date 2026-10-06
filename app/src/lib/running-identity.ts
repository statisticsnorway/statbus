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

export function parseArtifactSHA(payload: unknown): string | null {
  if (
    typeof payload !== "object" ||
    payload === null ||
    !("commit_sha" in payload)
  )
    return null;
  return typeof payload.commit_sha === "string" &&
    /^[0-9a-f]{40}$/.test(payload.commit_sha)
    ? payload.commit_sha
    : null;
}

export function parseRunningIdentity(
  payload: unknown,
  artifactSHA: string | null
): RunningIdentity | null {
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
    !artifactSHA ||
    candidate.commit_sha !== artifactSHA ||
    !/^[0-9a-f]{40}$/.test(artifactSHA) ||
    typeof candidate.resolved_name !== "string" ||
    candidate.resolved_name.trim().length === 0 ||
    typeof candidate.release_status !== "string" ||
    !["commit", "prerelease", "release"].includes(candidate.release_status) ||
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
  artifactSHA: string | null
): RunningVersionDisplay {
  return {
    name: runningIdentity?.resolved_name ?? "unknown",
    commit: artifactSHA ? displayCommit(artifactSHA) : null,
  };
}
