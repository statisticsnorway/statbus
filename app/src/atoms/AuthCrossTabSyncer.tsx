"use client";

import { useEffect } from 'react';
import { useAtom, useAtomValue, useSetAtom } from 'jotai';
import { clientMountedAtom, restClientAtom } from './app';
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

  useEffect(() => {
    // Don't run until the client is mounted AND the REST client is ready.
    if (!clientMounted || !restClient) {
      return;
    }

    // This condition handles both the initial fetch (when lastSyncTs is null)
    // and subsequent updates from other tabs.
    if (lastSyncTs === null || lastSyncTs !== authChangeTimestamp) {
      fetchAuthStatus();
      setLastSyncTs(authChangeTimestamp);
    }
  }, [clientMounted, restClient, authChangeTimestamp, lastSyncTs, setLastSyncTs, fetchAuthStatus]);

  return null;
};
