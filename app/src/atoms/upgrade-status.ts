"use client";

import { atom } from 'jotai'
import { loadable } from 'jotai/utils'
import { atomWithRefresh } from 'jotai/utils'

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
        .from("upgrade" as any)
        .select("started_at,scheduled_at")
        .is("completed_at", null)
        .is("rollback_completed_at", null)
        .is("skipped_at", null)
        .order("discovered_at", { ascending: false })
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
    default:
      return null;
  }
});
