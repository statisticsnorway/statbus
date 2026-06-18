"use client";

import { atom } from 'jotai'
import { loadable } from 'jotai/utils'
import { atomWithRefresh } from 'jotai/utils'
import { atomEffect } from 'jotai-effect'

import { restClientAtom } from './rest-client'
import { authStateForDataFetchingAtom } from './auth'

export type UpgradeStatus = "available" | "scheduled" | "in_progress";

interface PendingUpgrade {
  started_at: string | null;
  scheduled_at: string | null;
}

function getUpgradeStatus(u: PendingUpgrade): UpgradeStatus {
  if (u.started_at) return "in_progress";
  if (u.scheduled_at) return "scheduled";
  return "available";
}

export const pendingUpgradePromiseAtom = atomWithRefresh<Promise<UpgradeStatus | null>>(
  async (get): Promise<UpgradeStatus | null> => {
    const authState = get(authStateForDataFetchingAtom);
    const client = get(restClientAtom);

    if (authState === 'refreshing' || authState === 'checking') {
      return new Promise<never>(() => {});
    }

    if (authState !== 'authenticated' || !client) {
      return null;
    }

    try {
      const { data, error } = await client
        .from("upgrade")
        .select("started_at,scheduled_at")
        .is("completed_at", null)
        .is("rolled_back_at", null)
        .is("skipped_at", null)
        .is("superseded_at", null)
        .is("error", null)
        .order("committed_at", { ascending: false })
        .limit(1);

      if (error || !data || data.length === 0) {
        return null;
      }

      return getUpgradeStatus(data[0] as unknown as PendingUpgrade);
    } catch {
      return null;
    }
  }
);

export const pendingUpgradeLoadableAtom = loadable(pendingUpgradePromiseAtom);

export const pendingUpgradeStatusAtom = atom<UpgradeStatus | null>((get) => {
  const loadableState = get(pendingUpgradeLoadableAtom);
  switch (loadableState.state) {
    case 'hasData':
      return loadableState.data;
    case 'loading':
      // Retain the previous resolved value during a poll-triggered refresh so
      // consumers don't flicker to null while the fetch is in flight (STATBUS-090).
      return ((loadableState as { data?: UpgradeStatus | null }).data) ?? null;
    default:
      return null;
  }
});

// While a pending/in_progress upgrade is active, poll the upgrade row every
// 4 s independent of the SSE connection. This ensures the UI stays current
// even if the SSE gives up reconnecting during the maintenance window
// (STATBUS-090: SSE exhausts ~31 s of backoff while the upgrade takes minutes).
// Activate by reading this atom in a top-level component (see AppInitializer).
const UPGRADE_POLL_INTERVAL_MS = 4000;

export const upgradePollingEffectAtom = atomEffect((get, set) => {
  const status = get(pendingUpgradeStatusAtom);
  if (status !== 'in_progress' && status !== 'scheduled') return;

  const interval = setInterval(() => {
    set(pendingUpgradePromiseAtom);
  }, UPGRADE_POLL_INTERVAL_MS);

  return () => clearInterval(interval);
});
