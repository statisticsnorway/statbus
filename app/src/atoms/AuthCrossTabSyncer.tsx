"use client";

import { useRef } from 'react';
import { useGuardedEffect } from '@/hooks/use-guarded-effect';
import { useAtom, useAtomValue, useSetAtom } from 'jotai';
import { clientMountedAtom } from './app';
import { restClientAtom } from './rest-client';
import {
  authChangeTriggerAtom,
  fetchAuthStatusAtom,
  lastSyncTimestampAtom,
} from './auth';

/**
 * AuthCrossTabSyncer
 * 
 * This component's sole responsibility is to listen for authentication events
 * from other browser tabs and trigger a refresh of the current tab's auth state.
 * 
 * It uses `atomWithStorage` (`authEventTimestampAtom`) which leverages the
 * `storage` event to communicate between tabs.
 * 
 * It does NOT contain any logic for redirecting. That logic is handled by
 * components that react to the resulting change in the auth state, such as
 * `LoginClientBoundary` or effects in `JotaiAppProvider`.
 */
export const AuthCrossTabSyncer = () => {
  const clientMounted = useAtomValue(clientMountedAtom);
  const restClient = useAtomValue(restClientAtom);
  const authChangeTimestamp = useAtomValue(authChangeTriggerAtom); // From storage
  const [lastSyncTs, setLastSyncTs] = useAtom(lastSyncTimestampAtom); // Local state
  const fetchAuthStatus = useSetAtom(fetchAuthStatusAtom);
  const isInitialMount = useRef(true);

  useGuardedEffect(() => {
    // Don't run until the client is mounted AND the REST client is ready.
    if (!clientMounted || !restClient) {
      return;
    }

    // On the initial mount, we just want to synchronize our local timestamp
    // with the one from storage, without triggering a fetch. AppInitializer
    // is responsible for the very first fetch.
    if (isInitialMount.current) {
      setLastSyncTs(authChangeTimestamp);
      isInitialMount.current = false;
      return;
    }

    // On subsequent runs, if the timestamp from storage has changed, it means
    // another tab performed an auth action, so we need to sync this tab.
    if (lastSyncTs !== authChangeTimestamp) {
      fetchAuthStatus();
      setLastSyncTs(authChangeTimestamp);
    }
  }, [clientMounted, restClient, authChangeTimestamp, lastSyncTs, setLastSyncTs, fetchAuthStatus], 'AuthCrossTabSyncer:sync');

  return null;
};
