export interface UpgradeOrderingCandidate {
  display_name: string;
  release_status: "commit" | "prerelease" | "release";
  committed_at: string;
}

const statusRank: Record<UpgradeOrderingCandidate["release_status"], number> = {
  release: 3,
  prerelease: 2,
  commit: 1,
};

function calendarVersionParts(version: string): Array<number | string> | null {
  const normalized = version.replace(/^v+/, "");
  if (!/^\d{4}\.\d{2}\.\d+(?:-[\w.]+)?$/.test(normalized)) {
    return null;
  }

  return normalized
    .split(/[.-]/)
    .map((part) => (/^\d+$/.test(part) ? Number(part) : part));
}

export function compareCalendarVersions(a: string, b: string): number {
  const aParts = calendarVersionParts(a);
  const bParts = calendarVersionParts(b);
  if (!aParts || !bParts) return 0;

  const commonLength = Math.min(aParts.length, bParts.length);
  for (let index = 0; index < commonLength; index += 1) {
    const aPart = aParts[index];
    const bPart = bParts[index];
    if (aPart === bPart) continue;
    if (typeof aPart === "number" && typeof bPart === "number") {
      return aPart > bPart ? 1 : -1;
    }
    return String(aPart).localeCompare(String(bPart));
  }

  // A clean release is newer than a prerelease of the same calendar version.
  if (aParts.length !== bParts.length) {
    return aParts.length < bParts.length ? 1 : -1;
  }
  return 0;
}

export function compareUpgradeCandidates(
  a: UpgradeOrderingCandidate,
  b: UpgradeOrderingCandidate
): number {
  const tierDifference =
    statusRank[b.release_status] - statusRank[a.release_status];
  if (tierDifference !== 0) return tierDifference;

  const versionDifference = compareCalendarVersions(
    a.display_name,
    b.display_name
  );
  if (versionDifference !== 0) return -versionDifference;

  return Date.parse(b.committed_at) - Date.parse(a.committed_at);
}
