"use client";

import React, { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAtomValue } from "jotai";
import { authStatusAtom, authStatusInitiallyCheckedAtom } from "@/atoms"; // Added authStatusInitiallyCheckedAtom
import LoginForm from "./LoginForm"; // LoginForm.tsx is in the same directory

export default function LoginClientBoundary() {
  const router = useRouter();
  const authStatus = useAtomValue(authStatusAtom);
  const initialAuthCheckCompleted = useAtomValue(authStatusInitiallyCheckedAtom);

  useEffect(() => {
    const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';

    if (debug) {
      console.log("LoginClientBoundary useEffect triggered. Current states:", {
        initialAuthCheckCompleted,
        isAuthenticated: authStatus.isAuthenticated,
        authLoading: authStatus.loading,
        hasUser: !!authStatus.user,
        errorCode: authStatus.error_code,
      });
    }

    // Only attempt redirect if the initial auth check is complete and not currently loading.
    // This prevents redirect attempts based on potentially stale or intermediate auth states.
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
      if (debug) {
        console.log("LoginClientBoundary: Conditions met for redirect: initialAuthCheckCompleted=true, authLoading=false, isAuthenticated=true. Redirecting to /");
      }
      router.push('/'); // Redirect to home, middleware should handle further redirection if needed.
    } else {
      if (debug) {
        console.log("LoginClientBoundary: Conditions for redirect NOT met: initialAuthCheckCompleted=true, authLoading=false, but isAuthenticated=false. No redirect from login page.");
      }
    }
    // Adding authStatus.isAuthenticated, authStatus.loading, authStatus.user, authStatus.error_code, 
    // and initialAuthCheckCompleted to the dependency array
    // ensures this effect re-evaluates when these crucial state markers change.
  }, [
    authStatus.isAuthenticated, 
    authStatus.loading, 
    authStatus.user, // Added based on ESLint suggestion
    authStatus.error_code, // Added based on ESLint suggestion
    initialAuthCheckCompleted, 
    router
  ]);

  // Render the LoginForm. The useEffect above will handle redirection if/when auth state changes
  // and the initial auth check has been completed.
  return <LoginForm />;
}
