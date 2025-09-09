"use client";

import { useRef } from 'react';
import { useGuardedEffect } from '@/hooks/use-guarded-effect';
import { useAtomValue, useSetAtom, useAtom } from 'jotai';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';

import {
  navigationMachineAtom,
  type NavigationContext,
} from './navigation-machine';
import {
  lastKnownPathBeforeAuthChangeAtom,
  authStatusDetailsAtom,
  isUserConsideredAuthenticatedForUIAtom,
  authMachineAtom,
  isAuthStableAtom,
} from './auth';
import { clientMountedAtom, setupRedirectCheckAtom, debugInspectorVisibleAtom, saveJournalSnapshotAtom } from './app';

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
  const isAuthenticated = useAtomValue(isUserConsideredAuthenticatedForUIAtom);
  const authDetails = useAtomValue(authStatusDetailsAtom);
  const isAuthLoading = authDetails.loading;
  const isAuthStable = useAtomValue(isAuthStableAtom);
  const setupRedirectCheck = useAtomValue(setupRedirectCheckAtom);
  const clientMounted = useAtomValue(clientMountedAtom);
  const [lastKnownPath, setLastKnownPath] = useAtom(
    lastKnownPathBeforeAuthChangeAtom
  );
  const saveJournalSnapshot = useSetAtom(saveJournalSnapshotAtom);

  const [state, send] = useAtom(navigationMachineAtom);
  const [, sendAuth] = useAtom(authMachineAtom);
  const isInspectorVisible = useAtomValue(debugInspectorVisibleAtom);

  // This ref allows us to access the latest value of isInspectorVisible inside
  // the effect without making it a dependency, which would violate conventions.
  const inspectorVisibleRef = useRef(isInspectorVisible);
  inspectorVisibleRef.current = isInspectorVisible;

  // Effect to send context updates to the machine on every render
  useGuardedEffect(() => {
    if (!clientMounted) return;

    const context: Partial<Omit<NavigationContext, 'sideEffect'>> = {
      pathname,
      isAuthenticated,
      isAuthLoading,
      isAuthStable,
      setupPath: setupRedirectCheck.path,
      isSetupLoading: setupRedirectCheck.isLoading,
      lastKnownPath,
    };
    if (inspectorVisibleRef.current) {
      // Add detailed logging to trace the context being sent to the machine.
      console.log('[NavigationManager] Sending CONTEXT_UPDATED', context);
    }
    send({ type: 'CONTEXT_UPDATED', value: context });
  }, [
    clientMounted,
    pathname,
    isAuthenticated,
    isAuthLoading,
    isAuthStable,
    setupRedirectCheck.path,
    setupRedirectCheck.isLoading,
    lastKnownPath,
    send,
  ], 'NavigationManager:sendContextUpdates');

  // De-structure state for the effect dependency array to prevent unnecessary re-runs.
  // This is a critical performance optimization that adheres to our conventions.
  const stateValue = state.value;
  const sideEffect = state.context.sideEffect;

  // Effect to perform side-effects based on the machine's state
  useGuardedEffect(() => {
    const { targetPath, action } = sideEffect || {};

    // The logic to prevent infinite loops is now handled inside the state machine's
    // CONTEXT_UPDATED event guard. We can now execute side-effects synchronously.
    if (action === 'navigateAndSaveJournal' && targetPath && targetPath !== pathname) {
      saveJournalSnapshot();
      // BATTLE WISDOM: Deferring router.push with a setTimeout(..., 0) is critical
      // to break out of the current React render cycle. This gives the browser a
      // moment to process pending events, such as updating its cookie store after a
      // token refresh, before the navigation request is sent to the server. Without
      // this, the server may receive the navigation request with a stale cookie and
      // incorrectly redirect back to the login page, causing an infinite loop.
      setTimeout(() => router.push(targetPath), 0);
    } else if (action === 'revalidateAuth') {
      sendAuth({ type: 'CHECK' });
    } else if (action === 'savePath') {
      const fullPath = `${pathname}${search ? `?${search}` : ''}`;
      if (pathname !== '/login') {
        setLastKnownPath(fullPath);
      }
    } else if (action === 'clearLastKnownPath') {
      setLastKnownPath(null);
    }
  }, [
    stateValue,
    sideEffect,
    pathname,
    search,
    router,
    setLastKnownPath,
    sendAuth,
    saveJournalSnapshot,
  ], 'NavigationManager:performSideEffects');

  return null;
};
