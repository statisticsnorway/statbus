"use client";

import { useEffect, useRef } from 'react';
import { useAtom, useAtomValue, useSetAtom } from 'jotai';
import {
  authEventTimestampAtom,
  authStatusCoreAtom,
  authStatusAtom,
  authStatusLoadableAtom,
  pendingRedirectAtom,
  lastKnownPathBeforeAuthChangeAtom,
} from './index';
import { usePathname, useSearchParams } from 'next/navigation';

export const AuthCrossTabSyncer = () => {
  const [eventTimestamp] = useAtom(authEventTimestampAtom);
  const refreshAuthStatusCore = useSetAtom(authStatusCoreAtom);
  const authStatus = useAtomValue(authStatusAtom); // Snapshot of auth status when effect runs
  const authLoadable = useAtomValue(authStatusLoadableAtom);
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const [lastPath, setLastPath] = useAtom(lastKnownPathBeforeAuthChangeAtom);

  const pathname = usePathname();
  const searchParams = useSearchParams();

  const lastProcessedTimestampRef = useRef<number>(eventTimestamp);
  // previousAuthRef will now be set only when a new cross-tab event is detected.
  const previousAuthRef = useRef<boolean>(authStatus.isAuthenticated); 

  // Removed the useEffect that was updating previousAuthRef on every authStatus.isAuthenticated change.

  useEffect(() => {
    const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';

    if (eventTimestamp === lastProcessedTimestampRef.current) {
      // Event is from this tab or already processed, or initial load with same timestamp
      return;
    }

    if (debug) {
      console.log(`AuthCrossTabSyncer: Detected auth event. Timestamp: ${eventTimestamp}, Last processed: ${lastProcessedTimestampRef.current}. Current auth before potential refresh: ${authStatus.isAuthenticated}`);
    }
    
    // Capture the auth state *before* initiating a refresh due to a cross-tab event.
    previousAuthRef.current = authStatus.isAuthenticated;

    // Store current path *before* auth refresh if user was authenticated.
    const currentFullPath = `${pathname}${searchParams.toString() ? `?${searchParams.toString()}` : ''}`;
    if (authStatus.isAuthenticated && pathname !== '/login') {
      if (debug) {
        console.log(`AuthCrossTabSyncer: User was authenticated on "${currentFullPath}". Storing as lastKnownPathBeforeAuthChange.`);
      }
      setLastPath(currentFullPath);
    }

    if (debug) {
      console.log("AuthCrossTabSyncer: Refreshing auth status core atom due to cross-tab event.");
    }
    // Mark this timestamp as being processed BEFORE triggering the refresh
    lastProcessedTimestampRef.current = eventTimestamp;
    refreshAuthStatusCore();
    // The logic to handle the post-refresh state will be in the next useEffect,
    // which watches authLoadable.state.

  }, [eventTimestamp, refreshAuthStatusCore, authStatus.isAuthenticated, pathname, searchParams, setLastPath]);


  // This separate effect waits for the auth status to stabilize after a refresh.
  useEffect(() => {
    const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';
    
    if (authLoadable.state === 'loading') {
      // Still loading, wait for it to stabilize
      return;
    }

    // Auth status is now stable (hasData or hasError)
    // This effect runs when authLoadable.state changes. We need to ensure it only acts
    // in response to a cross-tab event that has just completed refreshing.
    // The `lastProcessedTimestampRef.current === eventTimestamp` check helps,
    // but we also need to know the state *before* this refresh.
    
    const newAuthIsAuthenticated = authStatus.isAuthenticated; // Current (post-refresh) auth state
    const oldAuthWasAuthenticated = previousAuthRef.current; // Auth state before this refresh cycle began

    if (debug) {
        console.log(`AuthCrossTabSyncer: Auth status stabilized. Old auth: ${oldAuthWasAuthenticated}, New auth: ${newAuthIsAuthenticated}. Pathname: ${pathname}`);
    }

    if (oldAuthWasAuthenticated && !newAuthIsAuthenticated) {
      // User was logged in, now logged out
      if (pathname !== '/login') {
        const currentFullPath = `${pathname}${searchParams.toString() ? `?${searchParams.toString()}` : ''}`;
        // If the user was on the root path ('/'), redirect to '/login' without 'next'.
        // Otherwise, include the 'next' parameter.
        const redirectTarget = (pathname === '/' && !searchParams.toString()) 
          ? '/login' 
          : `/login?next=${encodeURIComponent(currentFullPath)}`;
        if (debug) {
          console.log(`AuthCrossTabSyncer: Transitioned to logged out. Current path: "${currentFullPath}". Redirecting to: "${redirectTarget}"`);
        }
        setPendingRedirect(redirectTarget);
      } else {
        if (debug) {
          console.log(`AuthCrossTabSyncer: Transitioned to logged out, but already on /login. No redirect.`);
        }
      }
    } else if (!oldAuthWasAuthenticated && newAuthIsAuthenticated) {
      // User was logged out, now logged in
      if (pathname === '/login') {
        const intendedRedirect = lastPath || '/';
        if (debug) {
          console.log(`AuthCrossTabSyncer: Transitioned to logged in while on /login. Redirecting to: ${intendedRedirect}`);
        }
        setPendingRedirect(intendedRedirect);
        setLastPath(null); 
      } else {
         if (debug) {
            console.log(`AuthCrossTabSyncer: Transitioned to logged in, not on /login (on "${pathname}"). No redirect needed from here.`);
         }
      }
    }
    // Update previousAuthRef here as well, after processing the transition
    previousAuthRef.current = newAuthIsAuthenticated;

  // Watch authLoadable.state to trigger after loading, and other relevant states.
  // Removed eventTimestamp from dependencies as the first effect handles initiating based on it.
  }, [authLoadable.state, authStatus.isAuthenticated, pathname, searchParams, lastPath, setLastPath, setPendingRedirect]);

  return null;
};
