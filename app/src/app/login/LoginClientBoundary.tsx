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
    // Only attempt redirect if the initial auth check is complete and not currently loading.
    // This prevents redirect attempts based on potentially stale or intermediate auth states.
    if (!initialAuthCheckCompleted || authStatus.loading) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("LoginClientBoundary: Waiting for initial auth check to complete or loading to finish.", { initialAuthCheckCompleted, authLoading: authStatus.loading });
      }
      return; // Wait for auth state to stabilize
    }

    if (authStatus.isAuthenticated) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("LoginClientBoundary: User is authenticated and initial check complete, redirecting to /");
      }
      router.push('/'); // Redirect to home, middleware should handle further redirection if needed.
    } else {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("LoginClientBoundary: User is not authenticated after initial check. No redirect from login page.");
      }
    }
    // Adding authStatus.loading and initialAuthCheckCompleted to the dependency array
    // ensures this effect re-evaluates when these crucial state markers change.
  }, [authStatus.isAuthenticated, authStatus.loading, initialAuthCheckCompleted, router]);

  // Render the LoginForm. The useEffect above will handle redirection if/when auth state changes
  // and the initial auth check has been completed.
  return <LoginForm />;
}
