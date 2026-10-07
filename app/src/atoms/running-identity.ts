import { atom } from "jotai";
import {
  parseArtifactSHA,
  parseRunningIdentity,
  type RunningIdentity,
} from "@/lib/running-identity";

export const artifactSHAAtom = atom<string | null>(null);
export const runningIdentityAtom = atom<RunningIdentity | null>(null);

// A single in-flight refresh prevents an old response overwriting rollback proof.
export const refreshRunningIdentityAtom = atom(null, async (get, set) => {
  if (get(refreshingAtom)) return;
  set(refreshingAtom, true);
  let artifactSHA: string | null = null;
  let runningIdentity: RunningIdentity | null = null;
  const previousIdentity = get(runningIdentityAtom);
  try {
    const artifact = await fetch("/_statbus-build.json", { cache: "no-store" });
    if (artifact.ok) artifactSHA = parseArtifactSHA(await artifact.json());
    if (artifactSHA) {
      const response = await fetch(
        `/rest/rpc/release_identity?p_commit_sha=${artifactSHA}`,
        {
          credentials: "include",
          cache: "no-store",
        }
      );
      if (response.ok)
        runningIdentity = parseRunningIdentity(
          await response.json(),
          artifactSHA
        );
    }
  } catch {
    // Missing legacy artifacts and unavailable metadata never prove a label.
  } finally {
    set(artifactSHAAtom, artifactSHA);
    // Keep the last PROVEN label while a refresh is in flight (previously the
    // 30s poll blanked it to "unknown" mid-refresh). Replace it only with a
    // newly proven one; drop it only when the artifact itself changed — an
    // old label must never describe a new artifact.
    if (runningIdentity) {
      set(runningIdentityAtom, runningIdentity);
    } else if (previousIdentity?.commit_sha !== artifactSHA) {
      set(runningIdentityAtom, null);
    }
    set(refreshingAtom, false);
  }
});
const refreshingAtom = atom(false);
