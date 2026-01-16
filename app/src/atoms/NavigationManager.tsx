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
import { clientMountedAtom, debugInspectorVisibleAtom, saveJournalSnapshotAtom } from './app';
import { setupRedirectCheckAtom } from './app-derived';

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
  const sideEffectStartTime = state.context.sideEffectStartTime;
  const sideEffectStartPathname = state.context.sideEffectStartPathname;

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

  // INTENT: TOO FAST DETECTION - Poll for missed navigation signals while sideEffect is active
  // Problem: sideEffect executes and navigation completes before React's usePathname() can update
  // Solution: Check immediately, then poll every 300ms to detect pathname changes that weren't captured by normal render cycle
  //
  // DECLARATIVE APPROACH: The machine stores sideEffectStartPathname in context when sideEffect is set.
  // This component simply compares current pathname against that stored value - no mutable refs needed
  // for tracking "when did sideEffect start". The machine is the source of truth.
  const pollingTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  useGuardedEffect(() => {
    // Clear any existing timeout
    if (pollingTimeoutRef.current) {
      clearTimeout(pollingTimeoutRef.current);
      pollingTimeoutRef.current = null;
    }

    // No sideEffect active - nothing to poll for
    if (!sideEffect || !sideEffectStartPathname) {
      return;
    }

    // Capture inspector state at effect start for consistent logging within polling
    const debug = inspectorVisibleRef.current;

    if (debug) {
      console.log('[Polling] Starting navigation polling', {
        sideEffectStartPathname,
        currentPathname: pathname,
        sideEffect,
      });
    }

    // Function to check for navigation completion (uses current values from closure)
    const checkNavigation = () => {
      if (debug) {
        console.log('[Polling] checkNavigation tick', {
          startPathname: sideEffectStartPathname,
          currentPathname: pathname,
          sideEffectAction: sideEffect?.action,
          pathChanged: sideEffectStartPathname !== pathname,
        });
      }
      
      // Navigation completed: pathname changed from where we started
      if (pathname !== sideEffectStartPathname) {
        if (debug) {
          console.log('[Polling] FAST navigation detected!', {
            intent: 'TOO_FAST_DETECTION',
            startPathname: sideEffectStartPathname,
            currentPathname: pathname,
            sideEffect,
            duration: sideEffectStartTime ? Date.now() - sideEffectStartTime : 'unknown',
          });
        }
        
        // Clear sideEffect - machine will transition to idle via always guard
        send({ type: 'CLEAR_SIDE_EFFECT', reason: 'polling_detected_completion' });
        return; // Stop polling
      }
      
      // Navigation not yet complete - continue polling
      pollingTimeoutRef.current = setTimeout(checkNavigation, 300);
    };

    // IMMEDIATE CHECK: Handle TOO FAST scenarios right away (navigation may have already completed)
    checkNavigation();

    // Cleanup function
    return () => {
      if (pollingTimeoutRef.current) {
        clearTimeout(pollingTimeoutRef.current);
        pollingTimeoutRef.current = null;
      }
    };
  }, [sideEffect, sideEffectStartPathname, sideEffectStartTime, pathname, send], 'NavigationManager:pollingDetection');

  return null;
};
