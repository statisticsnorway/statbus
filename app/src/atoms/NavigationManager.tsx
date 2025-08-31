"use client";

import { useEffect, useRef } from 'react';
import { useAtomValue, useSetAtom, useAtom } from 'jotai';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';

import {
  navigationMachineAtom,
  type NavigationContext,
} from './navigation-machine';
import {
  lastKnownPathBeforeAuthChangeAtom,
  authStatusAtom,
} from './auth';
import { clientMountedAtom, setupRedirectCheckAtom, stateInspectorVisibleAtom } from './app';

/**
 * NavigationManager
 *
 * This component is the sole driver of the navigation state machine. It is responsible for:
 * 1. Gathering all necessary state from Jotai atoms.
 * 2. Sending this state to the XState machine on every render.
 * 3. Performing the side-effects (i.e., router.push) dictated by the machine's state.
 *
 * This centralizes all programmatic navigation logic, replacing the tangled web of
 * useEffects that existed in RedirectGuard and RedirectHandler.
 */
export const NavigationManager = () => {
  const router = useRouter();
  const pathname = usePathname();
  const search = useSearchParams().toString();

  // Gather all state dependencies for the machine
  const authStatus = useAtomValue(authStatusAtom);
  const setupRedirectCheck = useAtomValue(setupRedirectCheckAtom);
  const clientMounted = useAtomValue(clientMountedAtom);
  const [lastKnownPath, setLastKnownPath] = useAtom(
    lastKnownPathBeforeAuthChangeAtom
  );

  const [state, send] = useAtom(navigationMachineAtom);
  const stateRef = useRef(state);
  stateRef.current = state;
  const isInspectorVisible = useAtomValue(stateInspectorVisibleAtom);

  // Effect to send context updates to the machine on every render
  useEffect(() => {
    if (!clientMounted) return;

    const context: Partial<Omit<NavigationContext, 'sideEffect'>> = {
      pathname,
      isAuthenticated: authStatus.isAuthenticated,
      isAuthLoading: authStatus.loading,
      setupPath: setupRedirectCheck.path,
      isSetupLoading: setupRedirectCheck.isLoading,
      lastKnownPath,
    };
    if (isInspectorVisible) {
      // Add detailed logging to trace the context being sent to the machine.
      console.log('[NavigationManager] Sending CONTEXT_UPDATED', context);
    }
    send({ type: 'CONTEXT_UPDATED', value: context });
  }, [
    clientMounted,
    pathname,
    authStatus.isAuthenticated,
    authStatus.loading,
    setupRedirectCheck.path,
    setupRedirectCheck.isLoading,
    lastKnownPath,
    send,
    isInspectorVisible,
  ]);

  // Effect to perform side-effects based on the machine's state
  useEffect(() => {
    // This effect should only run when the machine's state value changes.
    // We use a ref to prevent re-subscribing on every render.
    if (stateRef.current !== state) {
      stateRef.current = state;
    }

    const { targetPath, action } = state.context.sideEffect || {};

    // The logic to prevent infinite loops is now handled inside the state machine's
    // CONTEXT_UPDATED event guard. We can now execute side-effects synchronously.
    if (action === 'navigate' && targetPath && targetPath !== pathname) {
      // Navigation is still deferred slightly to ensure the URL updates cleanly
      // before the machine re-evaluates the new page state.
      setTimeout(() => router.push(targetPath), 0);
    } else if (action === 'savePath') {
      const fullPath = `${pathname}${search ? `?${search}` : ''}`;
      if (pathname !== '/login') {
        setLastKnownPath(fullPath);
      }
    } else if (action === 'clearLastKnownPath') {
      setLastKnownPath(null);
    }
  }, [state, pathname, search, router, setLastKnownPath]);

  return null;
};
