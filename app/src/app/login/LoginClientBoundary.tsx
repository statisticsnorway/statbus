"use client";

import React, { useEffect, useRef } from "react"; // Import useRef
import { useRouter, useSearchParams, usePathname } from "next/navigation"; // Added usePathname
import { useAtomValue, useSetAtom, useAtom } from "jotai"; // Added useAtom
import { authStatusAtom, authStatusInitiallyCheckedAtom, pendingRedirectAtom, loginActionInProgressAtom, lastKnownPathBeforeAuthChangeAtom } from "@/atoms"; // Added loginActionInProgressAtom and lastKnownPathBeforeAuthChangeAtom
import LoginForm from "./LoginForm"; // LoginForm.tsx is in the same directory

export default function LoginClientBoundary() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const nextPath = searchParams.get('next');
  const authStatus = useAtomValue(authStatusAtom);
  const initialAuthCheckCompleted = useAtomValue(authStatusInitiallyCheckedAtom);
  const pendingRedirectValue = useAtomValue(pendingRedirectAtom);
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const loginActionIsActive = useAtomValue(loginActionInProgressAtom); // Read the new flag
  const [lastPathBeforeAuthChange, setLastPathBeforeAuthChange] = useAtom(lastKnownPathBeforeAuthChangeAtom);
  const pathname = usePathname(); // Get current pathname
  const redirectInitiatedByThisInstanceRef = useRef(false);

  useEffect(() => {
    const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';

    if (debug) {
      console.log("LoginClientBoundary useEffect triggered. Current states:", {
        initialAuthCheckCompleted,
        isAuthenticated: authStatus.isAuthenticated,
        authLoading: authStatus.loading,
        hasUser: !!authStatus.user,
        errorCode: authStatus.error_code,
        pendingRedirect: pendingRedirectValue,
        loginActionIsActive, // Log the flag
        nextPathFromUrl: nextPath,
      });
    }

    // Only attempt redirect if the initial auth check is complete and not currently loading.
    if (!initialAuthCheckCompleted) {
      if (debug) {
        console.log("LoginClientBoundary: Waiting for initial auth check to complete (initialAuthCheckCompleted is false).");
      }
      return; // Wait for auth state to stabilize
    }

    if (authStatus.loading) {
      if (debug) {
        console.log("LoginClientBoundary: Auth is currently loading (authStatus.loading is true). Waiting for auth state to stabilize.");
      }
      return; // Wait for auth state to stabilize
    }

    // At this point, initialAuthCheckCompleted is true AND authStatus.loading is false.
    // Now we can reliably check isAuthenticated.
    if (authStatus.isAuthenticated) {
      // Only act if:
      // 1. We are on the /login page.
      // 2. No other redirect is already pending (`pendingRedirectValue` is null).
      // 3. No login action is currently in progress.
      // 4. This specific instance of LoginClientBoundary has not already initiated a redirect.
      if (pathname === '/login' && pendingRedirectValue === null && !loginActionIsActive && !redirectInitiatedByThisInstanceRef.current) {
        // User is authenticated and on the login page, and no other redirect is active or initiated by this instance.
        // This means they landed here authenticated, or became authenticated via another tab.
        // Set pendingRedirectAtom. RedirectHandler will pick it up.
        
        let targetRedirectPath: string;
        if (lastPathBeforeAuthChange) {
          targetRedirectPath = lastPathBeforeAuthChange;
          if (debug) {
            console.log(`LoginClientBoundary: Using lastKnownPathBeforeAuthChange for redirect: "${targetRedirectPath}". Clearing it.`);
          }
          setLastPathBeforeAuthChange(null); // Clear after use
        } else {
          targetRedirectPath = nextPath && nextPath.startsWith('/') ? nextPath : '/';
        }
        
        if (debug) {
          console.log(`LoginClientBoundary: Authenticated on /login. Initiating redirect to "${targetRedirectPath}". Setting redirectInitiatedByThisInstanceRef to true.`);
        }
        setPendingRedirect(targetRedirectPath);
        redirectInitiatedByThisInstanceRef.current = true; // Mark that this instance has initiated a redirect
      } else {
        if (debug) {
          let reason = "";
          if (pathname !== '/login') reason += "Not on /login page. ";
          if (pendingRedirectValue !== null) reason += `Redirect already pending ("${pendingRedirectValue}"). `;
          if (loginActionIsActive) reason += "Login action is active. ";
          if (redirectInitiatedByThisInstanceRef.current && pathname === '/login') reason += "This instance already initiated a redirect. ";
          console.log(`LoginClientBoundary: Authenticated. Conditions to redirect NOT met: ${reason.trim()} No action here.`);
        }
      }
    } else {
      // User is not authenticated. Reset the flag if it was set.
      if (redirectInitiatedByThisInstanceRef.current) {
        if (debug) {
          console.log("LoginClientBoundary: User became unauthenticated. Resetting redirectInitiatedByThisInstanceRef to false.");
        }
        redirectInitiatedByThisInstanceRef.current = false;
      }
      if (debug) {
        console.log("LoginClientBoundary: User not authenticated. No redirect action from login page boundary.");
      }
    }
  }, [
    authStatus.isAuthenticated,
    authStatus.loading, // To ensure we act on stable auth state
    authStatus.user, // Added based on ESLint warning (indirectly used via authStatus object)
    authStatus.error_code, // Added based on ESLint warning (indirectly used via authStatus object)
    initialAuthCheckCompleted, // To ensure initial check is done
    pathname, // Current path
    nextPath, // From URL query
    pendingRedirectValue, // Current value of pendingRedirectAtom
    loginActionIsActive, // Is loginAtom currently handling a redirect
    setPendingRedirect, // To set the redirect
    lastPathBeforeAuthChange, // Add as dependency
    setLastPathBeforeAuthChange // Add as dependency
    // router is not needed here anymore as RedirectHandler does the push
  ]);

  // The loginActionInProgressAtom is set by loginAtom and cleared by RedirectHandler.
  // The hasAttemptedRedirectRef and its unmount effect are removed.

  // Render the LoginForm. The useEffect above will set pendingRedirectAtom if needed,
  // assuming the user lands on /login already authenticated and no login action is active.
  return <LoginForm nextPath={nextPath} />;
}
