export interface RunningIdentity {
  commit_sha: string;
  resolved_name: string;
  release_status: "commit" | "prerelease" | "release";
  build_name: string | null;
}

export interface RunningVersionDisplay {
  /** Release/build name; null when only the commit is known. */
  name: string | null;
  /** 8-char commit of the responding artifact; null when unproven. */
  commit: string | null;
  /** Where the name points: a release tag, or the exact commit. */
  href: string;
}

const REPO_URL = "https://github.com/statisticsnorway/statbus";

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

/**
 * The install-time name (`./sb config generate` writes `git describe --tags
 * --always` of the checkout as PUBLIC_STATBUS_VERSION, beside
 * PUBLIC_STATBUS_COMMIT_SHORT). It names the responding artifact only when
 * that configured commit IS the artifact's commit: after a rollback or a
 * half-finished upgrade the configured target may differ from what serves,
 * and a configured name must never describe another artifact. Placeholders
 * ("local", "unknown") and a bare commit hash (describe without tags) carry
 * no name.
 */
function configuredName(
  artifactSHA: string,
  fallbackVersion: string,
  fallbackCommit: string
): string | null {
  const version = fallbackVersion.trim();
  const commit = fallbackCommit.trim().toLowerCase();
  if (
    !/^[0-9a-f]{7,40}$/.test(commit) ||
    !artifactSHA.startsWith(commit) ||
    !version ||
    version === "local" ||
    version === "unknown" ||
    (/^[0-9a-f]{7,40}$/.test(version) && artifactSHA.startsWith(version))
  ) {
    return null;
  }
  return version;
}

/**
 * The one footer/admin label for the responding app (STATBUS-422):
 * 1. the ledger's release identity for the artifact SHA, else
 * 2. the install-time configured release name, bound to the artifact SHA, else
 * 3. no name, only the proven commit (rendered as "commit <sha8>").
 * "unknown" remains only when not even the artifact commit is proven.
 */
export function runningVersionDisplay(
  runningIdentity: RunningIdentity | null,
  artifactSHA: string | null,
  fallbackVersion = "",
  fallbackCommit = ""
): RunningVersionDisplay {
  const commit = artifactSHA ? displayCommit(artifactSHA) : null;
  if (runningIdentity) {
    return {
      name: runningIdentity.resolved_name,
      commit,
      href:
        runningIdentity.release_status === "commit"
          ? `${REPO_URL}/commit/${runningIdentity.commit_sha}`
          : `${REPO_URL}/releases/tag/${runningIdentity.resolved_name}`,
    };
  }
  if (!artifactSHA) {
    return { name: null, commit: null, href: `${REPO_URL}/` };
  }
  const name = configuredName(artifactSHA, fallbackVersion, fallbackCommit);
  return {
    name,
    commit,
    // An exact `git describe` tag names a release; anything else (a dev
    // describe like v2026.10.0-48-gd7ae1f231) links to the exact commit.
    href:
      name && /^v\d{4}\.\d{2}\.\d+(-rc\.\d+)?$/.test(name)
        ? `${REPO_URL}/releases/tag/${name}`
        : `${REPO_URL}/commit/${artifactSHA}`,
  };
}

/** Plain-text label: "v2026.10.0", "commit bce5bf39", or "unknown". */
export function runningVersionLabel(display: RunningVersionDisplay): string {
  if (display.name) return display.name;
  if (display.commit) return `commit ${display.commit}`;
  return "unknown";
}
