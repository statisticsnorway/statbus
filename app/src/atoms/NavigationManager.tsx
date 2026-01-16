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
    const debug = inspectorVisibleRef.current;

    // ALWAYS log when effect runs - we need to see if it's being triggered at all
    if (debug) {
      console.log('[performSideEffects] Effect triggered', {
        hasSideEffect: !!sideEffect,
        action: action ?? 'none',
        targetPath: targetPath ?? 'none',
        pathname,
        stateValue,
      });
    }

    // Early return if no sideEffect
    if (!sideEffect) {
      return;
    }

    // The logic to prevent infinite loops is now handled inside the state machine's
    // CONTEXT_UPDATED event guard. We can now execute side-effects synchronously.
    if (action === 'navigateAndSaveJournal' && targetPath && targetPath !== pathname) {
      if (debug) {
        console.log('[performSideEffects] EXECUTING navigateAndSaveJournal', { targetPath, pathname });
      }
      saveJournalSnapshot();
      // BATTLE WISDOM: Deferring router.push with a setTimeout(..., 0) is critical
      // to break out of the current React render cycle. This gives the browser a
      // moment to process pending events, such as updating its cookie store after a
      // token refresh, before the navigation request is sent to the server. Without
      // this, the server may receive the navigation request with a stale cookie and
      // incorrectly redirect back to the login page, causing an infinite loop.
      setTimeout(() => {
        if (debug) {
          console.log('[performSideEffects] CALLING router.push NOW', { targetPath });
        }
        try {
          router.push(targetPath);
          if (debug) {
            console.log('[performSideEffects] router.push returned (no error thrown)');
          }
        } catch (err) {
          // Always log errors - this is critical
          console.error('[performSideEffects] router.push THREW ERROR', err);
        }
      }, 0);
    } else if (action === 'revalidateAuth') {
      if (debug) {
        console.log('[performSideEffects] EXECUTING revalidateAuth');
      }
      sendAuth({ type: 'CHECK' });
    } else if (action === 'savePath') {
      const fullPath = `${pathname}${search ? `?${search}` : ''}`;
      if (pathname !== '/login') {
        if (debug) {
          console.log('[performSideEffects] EXECUTING savePath', { fullPath });
        }
        setLastKnownPath(fullPath);
      }
    } else if (action === 'clearLastKnownPath') {
      if (debug) {
        console.log('[performSideEffects] EXECUTING clearLastKnownPath');
      }
      setLastKnownPath(null);
    } else if (sideEffect && debug) {
      // Log when we have a sideEffect but didn't execute navigateAndSaveJournal
      console.log('[performSideEffects] sideEffect NOT executed as navigate', {
        action,
        targetPath,
        pathname,
        reason: !action ? 'no action' : 
                action !== 'navigateAndSaveJournal' ? 'not navigateAndSaveJournal action' :
                !targetPath ? 'no targetPath' :
                targetPath === pathname ? 'targetPath === pathname (already there)' : 'unknown',
      });
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

  // INTENT: TOO FAST DETECTION + TOO SLOW DETECTION via polling
  // Problem 1 (TOO FAST): sideEffect executes and navigation completes before React's usePathname() can update
  // Problem 2 (TOO SLOW): navigation fails/hangs and CONTEXT_UPDATED events stop arriving
  // Solution: Poll every 300ms using REFS to access current values (avoiding stale closure bug)
  //
  // DECLARATIVE APPROACH: The machine stores sideEffectStartPathname in context when sideEffect is set.
  // This component uses refs to always access the latest values during polling.
  const pollingTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  
  // Refs to access current values during polling (avoids stale closure bug)
  const currentPathnameRef = useRef(pathname);
  const currentSideEffectStartTimeRef = useRef(sideEffectStartTime);
  const currentSideEffectStartPathnameRef = useRef(sideEffectStartPathname);
  
  // Keep refs synchronized with latest values
  currentPathnameRef.current = pathname;
  currentSideEffectStartTimeRef.current = sideEffectStartTime;
  currentSideEffectStartPathnameRef.current = sideEffectStartPathname;

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
    const TIMEOUT_MS = 3000; // 3 seconds timeout for TOO SLOW detection

    if (debug) {
      console.log('[Polling] Starting navigation polling', {
        sideEffectStartPathname,
        currentPathname: pathname,
        sideEffect,
      });
    }

    // Function to check for navigation completion (uses REFS to access current values)
    const checkNavigation = () => {
      // Read current values from refs (not stale closure values)
      const currentPathname = currentPathnameRef.current;
      const startPathname = currentSideEffectStartPathnameRef.current;
      const startTime = currentSideEffectStartTimeRef.current;
      
      if (debug) {
        console.log('[Polling] checkNavigation tick', {
          startPathname,
          currentPathname,
          sideEffectAction: sideEffect?.action,
          pathChanged: startPathname !== currentPathname,
          elapsedMs: startTime ? Date.now() - startTime : 'unknown',
        });
      }
      
      // TOO FAST DETECTION: pathname changed from where we started
      if (startPathname && currentPathname !== startPathname) {
        if (debug) {
          console.log('[Polling] FAST navigation detected!', {
            intent: 'TOO_FAST_DETECTION',
            startPathname,
            currentPathname,
            sideEffect,
            duration: startTime ? Date.now() - startTime : 'unknown',
          });
        }
        
        // Clear sideEffect - machine will transition to idle via always guard
        send({ type: 'CLEAR_SIDE_EFFECT', reason: 'polling_detected_completion' });
        return; // Stop polling
      }
      
      // TOO SLOW DETECTION: navigation has been pending too long
      if (startTime && Date.now() - startTime > TIMEOUT_MS) {
        console.error('[Polling] Navigation TIMEOUT (too slow) - clearing sideEffect', {
          intent: 'TOO_SLOW_DETECTION',
          startPathname,
          currentPathname,
          sideEffect,
          duration: Date.now() - startTime,
        });
        
        // Clear sideEffect - machine will re-evaluate and try again or go to idle
        send({ type: 'CLEAR_SIDE_EFFECT', reason: 'timeout' });
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
  }, [sideEffect, sideEffectStartPathname, pathname, send], 'NavigationManager:pollingDetection');

  return null;
};
