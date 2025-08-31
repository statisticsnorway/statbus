"use client";

import React, { useEffect, useState } from "react";
import { useSearchParams, usePathname } from "next/navigation";
import { useAtomValue, useSetAtom, useAtom } from "jotai";
import { authMachineAtom, loginPageMachineAtom } from "@/atoms/auth";
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
  const [isMounted, setIsMounted] = useState(false);
  useEffect(() => {
    setIsMounted(true);
  }, []);

  const searchParams = useSearchParams();
  const nextPath = searchParams.get('next');
  const pathname = usePathname();
  const [authState] = useAtom(authMachineAtom);
  const [loginPageState, sendLoginPage] = useAtom(loginPageMachineAtom);

  useEffect(() => {
    // On every render, send the latest context to the UI state machine.
    // This allows the machine to react to changes in auth status or path.
    const isOnLoginPage = pathname === '/login';
    const isAuthenticated = authState.matches('idle_authenticated');
    const isLoggingIn = authState.matches('loggingIn');

    sendLoginPage({
      type: 'EVALUATE',
      context: { isOnLoginPage, isAuthenticated, isLoggingIn }
    });
  }, [pathname, authState, sendLoginPage]);

  if (!isMounted) {
    // During SSR and initial client render, render nothing to prevent hydration mismatch.
    // The server-rendered page will contain the static layout, but this dynamic
    // part will be blank, matching the initial client render.
    return null;
  }

  // Render content based on the local UI machine's state.
  if (loginPageState.matches('finalizing')) {
    return (
      <div className="text-center text-gray-500 pt-8">
        <p>Finalizing login...</p>
      </div>
    );
  }
  
  if (loginPageState.matches('showingForm')) {
    return <LoginForm nextPath={nextPath} />;
  }

  // In all other cases (e.g., 'idle', 'evaluating', or not on login page),
  // render nothing. The central NavigationManager handles redirects.
  return null;
}
