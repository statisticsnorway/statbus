export interface ArtifactUpgradeRow {
  commit_sha: string;
  committed_at: string;
}

export function currentAppRow<T extends ArtifactUpgradeRow>(
  artifactSHA: string | null,
  rows: T[] | undefined
): T | null {
  const row = rows?.length === 1 ? rows[0] : null;
  return artifactSHA &&
    row?.commit_sha === artifactSHA &&
    Number.isFinite(Date.parse(row.committed_at))
    ? row
    : null;
}

export function newerThanCurrentApp(
  candidate: ArtifactUpgradeRow,
  current: ArtifactUpgradeRow | null
): boolean {
  return (
    current !== null &&
    Date.parse(candidate.committed_at) > Date.parse(current.committed_at)
  );
}
