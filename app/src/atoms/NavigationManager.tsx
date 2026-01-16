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
  const lastPathnameRef = useRef(pathname);
  const pollingTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const currentPathnameRef = useRef(pathname);
  const currentSideEffectRef = useRef(sideEffect);
  const currentSideEffectStartTimeRef = useRef(sideEffectStartTime);
  
  // Keep refs updated
  currentPathnameRef.current = pathname;
  currentSideEffectRef.current = sideEffect;
  currentSideEffectStartTimeRef.current = sideEffectStartTime;

  useGuardedEffect(() => {
    // Clear any existing timeout
    if (pollingTimeoutRef.current) {
      clearTimeout(pollingTimeoutRef.current);
      pollingTimeoutRef.current = null;
    }

    // Function to check for navigation completion
    const checkNavigation = () => {
      const currentPathname = currentPathnameRef.current;
      const currentSideEffect = currentSideEffectRef.current;
      const currentStartTime = currentSideEffectStartTimeRef.current;
      
      if (currentSideEffect && currentPathname !== lastPathnameRef.current) {
        
        console.log('Navigation polling detected FAST pathname change', {
          intent: 'TOO_FAST_DETECTION',
          previousPathname: lastPathnameRef.current,
          currentPathname: currentPathname,
          sideEffect: currentSideEffect,
          duration: currentStartTime ? Date.now() - currentStartTime : 'unknown',
          reason: 'polling_detected_fast_navigation'
        });
        
        // TOO FAST RECOVERY: Clear sideEffect when polling detects navigation completion
        // For redirectingFromLogin: clear when pathname changes away from /login
        const shouldClearSideEffect = (
          (currentSideEffect.action === 'navigateAndSaveJournal' && 
           lastPathnameRef.current === '/login' && 
           currentPathname !== '/login') ||
          // Add other navigation completion patterns as needed
          (lastPathnameRef.current !== currentPathname)
        );
        
        if (shouldClearSideEffect) {
          console.log('Polling clearing sideEffect after fast navigation completion', {
            fromPathname: lastPathnameRef.current,
            toPathname: currentPathname,
            sideEffect: currentSideEffect
          });
          
          // First update the pathname
          send({ type: 'CONTEXT_UPDATED', value: { pathname: currentPathname } });
          
          // Then clear the sideEffect
          send({ type: 'CLEAR_SIDE_EFFECT', reason: 'polling_detected_completion' });
        } else {
          // Just send pathname update
          send({ type: 'CONTEXT_UPDATED', value: { pathname: currentPathname } });
        }
        
        lastPathnameRef.current = currentPathname;
        return; // Navigation completed, stop polling
      }
      
      // Continue polling if sideEffect is still active
      if (currentSideEffect) {
        pollingTimeoutRef.current = setTimeout(checkNavigation, 300);
      }
    };

    if (sideEffect) {
      // Capture the pathname when sideEffect is first set for comparison
      if (lastPathnameRef.current !== currentPathnameRef.current) {
        console.log('Capturing initial pathname for polling', {
          lastPathname: lastPathnameRef.current,
          currentPathname: currentPathnameRef.current,
          sideEffect: currentSideEffectRef.current
        });
      }
      
      // IMMEDIATE CHECK: Handle TOO FAST scenarios right away
      checkNavigation();
    }

    // Cleanup function
    return () => {
      if (pollingTimeoutRef.current) {
        clearTimeout(pollingTimeoutRef.current);
        pollingTimeoutRef.current = null;
      }
    };
  }, [sideEffect, send], 'NavigationManager:pollingDetection');

  return null;
};
