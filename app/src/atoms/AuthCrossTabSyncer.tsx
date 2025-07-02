"use client";

import { useEffect } from 'react';
import { useAtom, useAtomValue, useSetAtom } from 'jotai';
import {
  authChangeTriggerAtom,
  clientMountedAtom,
  lastSyncTimestampAtom,
  fetchAuthStatusAtom,
} from './index';

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
  const authChangeTimestamp = useAtomValue(authChangeTriggerAtom); // From storage
  const [lastSyncTs, setLastSyncTs] = useAtom(lastSyncTimestampAtom); // Local state
  const fetchAuthStatus = useSetAtom(fetchAuthStatusAtom);

  useEffect(() => {
    // Don't run until the client is mounted to ensure atoms are hydrated from storage.
    if (!clientMounted) {
      return;
    }

    const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';

    // This condition handles both the initial fetch (when lastSyncTs is null)
    // and subsequent updates from other tabs.
    if (lastSyncTs === null || lastSyncTs !== authChangeTimestamp) {
      if (debug) {
        console.log(`AuthCrossTabSyncer: Refreshing status. Reason: ${lastSyncTs === null ? 'Initial Load' : 'Timestamp changed'}.`);
      }
      fetchAuthStatus();
      setLastSyncTs(authChangeTimestamp);
    } else if (debug) {
      // console.log('AuthCrossTabSyncer: Timestamp is the same, no action needed.');
    }
  }, [clientMounted, authChangeTimestamp, lastSyncTs, setLastSyncTs, fetchAuthStatus]);

  return null;
};
