"use client";

import React, { useEffect, useState } from "react";
import { useSearchParams, usePathname } from "next/navigation";
import { useAtomValue, useSetAtom, useAtom } from "jotai";
import {
  authStatusAtom,
  authStatusInitiallyCheckedAtom,
  pendingRedirectAtom,
  loginActionInProgressAtom,
  lastKnownPathBeforeAuthChangeAtom,
  loginPageMachineAtom,
  clientMountedAtom,
} from "@/atoms";
import LoginForm from "./LoginForm";

/**
 * LoginClientBoundary
 * 
 * This component orchestrates the behavior of the /login page. It handles one primary case:
 * 
 * 1. Redirecting an authenticated user AWAY from the /login page.
 *    This can happen if:
 *    - A logged-in user directly navigates to /login.
 *    - A user on the /login page becomes authenticated via another tab (cross-tab sync).
 * 
 * It does NOT handle redirecting unauthenticated users TO the login page. That logic
 * is handled globally by an effect in `JotaiAppProvider`.
 */
export default function LoginClientBoundary() {
  const searchParams = useSearchParams();
  const nextPath = searchParams.get('next');
  const authStatus = useAtomValue(authStatusAtom);
  const initialAuthCheckCompleted = useAtomValue(authStatusInitiallyCheckedAtom);
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const [lastPathBeforeAuthChange, setLastPathBeforeAuthChange] = useAtom(lastKnownPathBeforeAuthChangeAtom);
  const pathname = usePathname();
  const [state, send] = useAtom(loginPageMachineAtom);
  const clientMounted = useAtomValue(clientMountedAtom);
  const [redirectAttempted, setRedirectAttempted] = useState(false);

  const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';

  // Effect to reset the machine to idle on mount. This ensures a clean state for every visit,
  // which is crucial for handling React 18 Strict Mode and Fast Refresh in development.
  useEffect(() => {
    // Only run after the client has mounted to ensure all state is hydrated.
    if (clientMounted) {
      send({ type: 'RESET' });
      setRedirectAttempted(false); // Also reset our local redirect flag
    }
  }, [clientMounted, send]);

  // Effect to send events to the state machine when dependencies change.
  useEffect(() => {
    // Gate this logic on clientMounted to ensure atomWithStorage has hydrated.
    if (!clientMounted) {
      return;
    }

    if (debug) {
      console.log(`LoginClientBoundary: State machine is in state: ${state.value}, auth status is isAuthenticated: ${authStatus.isAuthenticated}`);
      console.log(`LoginClientBoundary: Current lastKnownPathBeforeAuthChange is: "${lastPathBeforeAuthChange}"`);
    }

    // Once the initial auth check is done, we can evaluate.
    // This will run on first load and again if authStatus.isAuthenticated changes.
    if (initialAuthCheckCompleted) {
      if (debug) {
        console.log('LoginClientBoundary: Auth check complete, sending EVALUATE to state machine.');
      }
      send({
        type: 'EVALUATE',
        context: {
          isAuthenticated: authStatus.isAuthenticated,
          isOnLoginPage: pathname === '/login',
        },
      });
    }
  }, [clientMounted, initialAuthCheckCompleted, authStatus.isAuthenticated, pathname, send, debug]);

  // Effect to handle the side-effect of redirection when the machine enters the 'redirecting' state.
  useEffect(() => {
    // Gate this logic on clientMounted to ensure lastPathBeforeAuthChange is hydrated.
    if (!clientMounted) {
      return;
    }

    // This effect should only fire ONCE per visit, guarded by the redirectAttempted flag.
    if (state.matches('redirecting') && !redirectAttempted) {
      setRedirectAttempted(true); // Set the flag immediately to prevent re-entry.
      let targetRedirectPath: string;

      // Prioritize the path stored before a cross-tab auth change.
      if (lastPathBeforeAuthChange) {
        targetRedirectPath = lastPathBeforeAuthChange;
        if (debug) {
          console.log(`LoginClientBoundary: Using lastKnownPathBeforeAuthChange for redirect: "${targetRedirectPath}".`);
        }
      } else {
        // Otherwise, use the 'next' URL parameter or default to the dashboard.
        targetRedirectPath = nextPath && nextPath.startsWith('/') ? nextPath : '/';
      }

      if (debug) {
        console.log(`LoginClientBoundary: State machine entered 'redirecting' state. Setting pendingRedirectAtom to "${targetRedirectPath}".`);
      }
      
      setPendingRedirect(targetRedirectPath);
      // Clear the last path atom after using it for a redirect.
      setLastPathBeforeAuthChange(null);
    }
  }, [clientMounted, state.value, redirectAttempted, nextPath, lastPathBeforeAuthChange, setLastPathBeforeAuthChange, setPendingRedirect, debug]);

  // Render content based on the machine's state.
  if (state.matches('showingForm')) {
    return <LoginForm nextPath={nextPath} />;
  }

  // While idle or checking, render nothing or a skeleton loader.
  // Returning null is fine as the parent page provides the layout.
  return null;
}
