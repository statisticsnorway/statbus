"use client";

import React, { useEffect, useState } from "react";
import { useSearchParams, usePathname } from "next/navigation";
import { useAtomValue, useSetAtom, useAtom } from "jotai";
import { clientMountedAtom, pendingRedirectAtom, setupRedirectCheckAtom } from "@/atoms/app";
import {
  authStatusAtom,
  lastKnownPathBeforeAuthChangeAtom,
  loginPageMachineAtom,
} from "@/atoms/auth";
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
  const [pendingRedirect, setPendingRedirect] = useAtom(pendingRedirectAtom);
  const [lastPathBeforeAuthChange, setLastPathBeforeAuthChange] = useAtom(lastKnownPathBeforeAuthChangeAtom);
  const pathname = usePathname();
  const [state, send] = useAtom(loginPageMachineAtom);
  const clientMounted = useAtomValue(clientMountedAtom);
  const setupRedirectCheck = useAtomValue(setupRedirectCheckAtom);

  // Effect to reset the machine to idle on mount. This ensures a clean state for every visit,
  // which is crucial for handling React 18 Strict Mode and Fast Refresh in development.
  useEffect(() => {
    // Only run after the client has mounted to ensure all state is hydrated.
    if (clientMounted) {
      send({ type: 'RESET' });
    }
  }, [clientMounted, send]);

  // Effect to send events to the state machine when dependencies change.
  useEffect(() => {
    // Gate this logic on clientMounted to ensure atomWithStorage has hydrated,
    // and on authStatus.loading to ensure the auth check is complete.
    if (!clientMounted || authStatus.loading) {
      return;
    }

    // This will run on first load and again if authStatus.isAuthenticated changes.
    send({
      type: 'EVALUATE',
      context: {
        isAuthenticated: authStatus.isAuthenticated,
        isOnLoginPage: pathname === '/login',
      },
    });
  }, [clientMounted, authStatus.loading, authStatus.isAuthenticated, pathname, send]);

  // Effect to handle the side-effect of redirection when the machine is finalizing.
  useEffect(() => {
    // Gate this logic on clientMounted to ensure lastPathBeforeAuthChange is hydrated.
    if (!clientMounted) {
      return;
    }

    if (state.matches('finalizing')) {
      // Wait for the setup check to complete before deciding on a destination.
      if (setupRedirectCheck.isLoading) {
        return; // Still checking, do nothing. The effect will re-run when the atom updates.
      }

      // If a redirect is already pending, don't set another one.
      if (pendingRedirect !== null) {
        return;
      }
      
      const setupPath = setupRedirectCheck.path;
      let targetRedirectPath: string;

      if (setupPath) {
        // A required setup step takes highest priority.
        targetRedirectPath = setupPath;
      } else if (lastPathBeforeAuthChange) {
        // Then, restore the path from before a potential cross-tab auth change.
        targetRedirectPath = lastPathBeforeAuthChange;
      } else {
        // Otherwise, use the 'next' URL parameter or default to the dashboard.
        targetRedirectPath = nextPath && nextPath.startsWith('/') ? nextPath : '/';
      }
      
      // Final safeguard: ensure we never redirect back to the login page.
      const targetPathname = targetRedirectPath.split('?')[0];
      if (targetPathname === '/login') {
        targetRedirectPath = '/'; // Default to dashboard.
      }

      setPendingRedirect(targetRedirectPath);

      // If we used the last known path to create the redirect, clear it now
      // to prevent it from being reused on a subsequent visit to the login page
      // within the same session. This is the key to breaking the redirect loop
      // in passive auth refresh scenarios.
      if (lastPathBeforeAuthChange) {
        setLastPathBeforeAuthChange(null);
      }
    }
  }, [clientMounted, state, setupRedirectCheck, nextPath, lastPathBeforeAuthChange, pendingRedirect, setPendingRedirect, setLastPathBeforeAuthChange]);

  // Render content based on the machine's state.
  if (state.matches('finalizing')) {
    return (
      <div className="text-center text-gray-500 pt-8">
        <p>Finalizing login...</p>
      </div>
    );
  }

  if (state.matches('showingForm')) {
    return <LoginForm nextPath={nextPath} />;
  }

  // While idle or checking, render nothing or a skeleton loader.
  // Returning null is fine as the parent page provides the layout.
  return null;
}
