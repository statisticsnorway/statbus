"use client";

import React, { useEffect, useRef } from "react"; // Import useRef
import { useRouter, useSearchParams } from "next/navigation";
import { useAtomValue, useSetAtom } from "jotai";
import { authStatusAtom, authStatusInitiallyCheckedAtom, pendingRedirectAtom, loginActionInProgressAtom } from "@/atoms"; // Added loginActionInProgressAtom
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
  const hasAttemptedRedirectRef = useRef(false); // Tracks if this component instance has tried to redirect

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
      // If a redirect is already pending (e.g., set by loginAtom),
      // OR a login action is actively managing a redirect,
      // OR this instance has already attempted a redirect for the current authenticated session on this page,
      // let RedirectHandler manage it or do nothing further.
      if (pendingRedirectValue || loginActionIsActive || hasAttemptedRedirectRef.current) {
        if (debug) {
          console.log(`LoginClientBoundary: Authenticated. Conditions to skip setting redirect: pendingRedirectValue="${pendingRedirectValue}", loginActionIsActive=${loginActionIsActive}, hasAttemptedRedirectRef=${hasAttemptedRedirectRef.current}. No action here.`);
        }
        return;
      }

      // No redirect pending from loginAtom, no login action active, and this instance hasn't tried yet.
      // This means the user is authenticated either upon arrival or due to an external event.
      // Set pendingRedirectAtom. RedirectHandler will pick it up.
      // Target 'nextPath' if it exists from URL, otherwise '/'.
      const targetRedirectPath = nextPath && nextPath.startsWith('/') ? nextPath : '/';
      if (debug) {
        console.log(`LoginClientBoundary: Authenticated. No other redirect active or attempted by this instance. Setting pendingRedirectAtom to "${targetRedirectPath}".`);
      }
      setPendingRedirect(targetRedirectPath);
      hasAttemptedRedirectRef.current = true; // Mark that this instance has now attempted a redirect.
    } else {
      // If user becomes unauthenticated (e.g. token expires and status updates) while on the login page,
      // reset the flag so a new redirect attempt can be made if they re-authenticate without leaving.
      if (hasAttemptedRedirectRef.current) { // Only log if it was true
        if (debug) {
          console.log("LoginClientBoundary: User is not authenticated. Resetting hasAttemptedRedirectRef.");
        }
      }
      hasAttemptedRedirectRef.current = false;
      if (debug) {
        console.log("LoginClientBoundary: Conditions for setting a redirect NOT met: initialAuthCheckCompleted=true, authLoading=false, but isAuthenticated=false. No action from login page boundary.");
      }
    }
  }, [
    authStatus.isAuthenticated,
    authStatus.loading,
    authStatus.user,
    authStatus.error_code,
    initialAuthCheckCompleted,
    router, // router is stable, but included per ESLint rules for hooks
    nextPath, 
    pendingRedirectValue,
    setPendingRedirect, // setPendingRedirect is stable
    loginActionIsActive,
    // Add pathname to dependencies if used to scope the effect, though LoginClientBoundary is only on /login
  ]);

  // Unmount effect to reset the ref
  useEffect(() => {
    const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';
    return () => {
      if (debug) {
        console.log("LoginClientBoundary: Unmounting. Resetting hasAttemptedRedirectRef (final cleanup).");
      }
      // Note: hasAttemptedRedirectRef is a ref, its .current property is mutable
      // and doesn't need to be in a dependency array for its value to be up-to-date.
      // This cleanup ensures it's false if the component is fully removed.
      // hasAttemptedRedirectRef.current = false; // This line would modify the ref of the *next* render if not careful.
      // The ref itself persists across renders. The reset is handled by the main effect if auth state changes,
      // or on fresh mount the ref is new. The unmount cleanup is primarily for logical completeness if needed,
      // but the main effect's reset on `!isAuthenticated` is more critical for same-page re-auth.
      // For this specific case, an explicit unmount reset of the ref might not be strictly necessary
      // as a new mount will get a fresh `useRef(false)`.
    };
  }, []);


  // The loginActionInProgressAtom is now set by loginAtom and cleared by RedirectHandler.
  // No need for local ref management or unmount effect here for that atom.

  // Render the LoginForm. The useEffect above will set pendingRedirectAtom if needed,
  // assuming the user lands on /login already authenticated and no login action is active.
  return <LoginForm nextPath={nextPath} />;
}
