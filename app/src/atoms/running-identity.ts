import { atom } from "jotai";
import {
  parseRunningIdentity,
  type RunningIdentity,
} from "@/lib/running-identity";

export const runningIdentityAtom = atom<RunningIdentity | null>(null);

export const refreshRunningIdentityAtom = atom(null, async (_get, set) => {
  let runningIdentity: RunningIdentity | null = null;

  try {
    const response = await fetch("/rest/rpc/running_identity", {
      credentials: "include",
    });
    if (response.ok) {
      runningIdentity = parseRunningIdentity(await response.json());
    }
  } catch {
    // The injected build/install identity remains the explicit fallback.
  }

  set(runningIdentityAtom, runningIdentity);
});
