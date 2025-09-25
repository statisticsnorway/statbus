"use client";

import React from 'react';
import { useAtom, useAtomValue, useSetAtom } from 'jotai';
import { usePathname } from 'next/navigation';

// App state atoms
import {
  debugInspectorVisibleAtom,
  debugInspectorExpandedAtom,
  debugInspectorJournalVisibleAtom,
  debugInspectorStateVisibleAtom,
  debugInspectorApiLogExpandedAtom,
  debugInspectorEffectJournalVisibleAtom,
  debugInspectorMountJournalVisibleAtom,
  combinedJournalViewAtom,
  clearAndMarkJournalAtom,
  addEventJournalEntryAtom,
  requiredSetupRedirectAtom,
  selectedTimeContextAtom,
  initialAuthCheckCompletedAtom,
  MachineID,
} from '@/atoms/app';

// Auth state atoms
import {
  clientSideRefreshAtom,
  expireAccessTokenAtom,
  fetchAuthStatusAtom,
  authMachineAtom,
  isAuthActionInProgressAtom,
  authStatusDetailsAtom,
  isAuthenticatedStrictAtom,
  isUserConsideredAuthenticatedForUIAtom,
  lastKnownPathBeforeAuthChangeAtom,
  isTokenManuallyExpiredAtom,
} from '@/atoms/auth';

// Feature state atoms
import { baseDataAtom } from '@/atoms/base-data';
import { workerStatusAtom } from '@/atoms/worker_status';
import { queryAtom, filtersAtom, searchResultAtom, selectedUnitsAtom, paginationAtom, sortingAtom } from '@/atoms/search';
import { redirectRelevantStateAtom } from '@/atoms/app-derived';
import { navigationMachineAtom } from '@/atoms/navigation-machine';
import {
  isGuardingEnabled,
  haltedEffectsAtom,
  triggeredEffectsAtom,
  effectCallCountsAtom,
  effectRecentCallCountsAtom,
  mountCountsAtom,
  LOOP_DETECTION_WINDOW_MS,
  useGuardedEffect,
} from '@/hooks/use-guarded-effect';


// Helper to recursively calculate the difference between two objects.
const objectDiff = (obj1: any, obj2: any): any | undefined => {
  // Simple comparison for non-objects or if they are identical
  if (Object.is(obj1, obj2)) {
    return undefined;
  }
  // If one is not an object (or is null), return the change
  if (typeof obj1 !== 'object' || obj1 === null || typeof obj2 !== 'object' || obj2 === null) {
    return { oldValue: obj1, newValue: obj2 };
  }

  // For arrays, we'll do a simple stringify compare for brevity, not a deep diff
  if (Array.isArray(obj1) || Array.isArray(obj2)) {
    if (JSON.stringify(obj1) !== JSON.stringify(obj2)) {
      return { oldValue: obj1, newValue: obj2 };
    }
    return undefined;
  }

  const keys = [...new Set([...Object.keys(obj1), ...Object.keys(obj2)])];
  const diff: { [key: string]: any } = {};
  let hasChanges = false;

  for (const key of keys) {
    const result = objectDiff(obj1[key], obj2[key]);
    if (result !== undefined) {
      diff[key] = result;
      hasChanges = true;
    }
  }

  return hasChanges ? diff : undefined;
};

// Helper to format the diff object into a readable string for clipboard.
const formatDiffToString = (diff: any, path: string = ''): string => {
  let result = '';
  if (!diff) return '';
  for (const key in diff) {
    const newPath = path ? `${path}.${key}` : key;
    const value = diff[key];
    if (value && typeof value.oldValue !== 'undefined') {
      result += `- ${newPath}: ${JSON.stringify(value.oldValue)}\n`;
      result += `+ ${newPath}: ${JSON.stringify(value.newValue)}\n`;
    } else if (typeof value === 'object' && value !== null) {
      result += formatDiffToString(value, newPath);
    }
  }
  return result;
};

// Helper component to visually render the diff.
const StateDiff = ({ diff, path = '' }: { diff: any, path?: string }) => {
  if (!diff) return null;

  return (
    <div className="pl-2 border-l border-gray-600 font-mono">
      {Object.entries(diff).map(([key, value]: [string, any]) => {
        const newPath = path ? `${path}.${key}` : key;
        const hasNestedDiff = typeof value === 'object' && value !== null && !value.hasOwnProperty('oldValue');

        return (
          <div key={newPath}>
            <span className="text-gray-400">{key}:</span>
            {hasNestedDiff ? (
              <StateDiff diff={value} path={newPath} />
            ) : (
              <div className="pl-2">
                <div className="text-red-400 whitespace-pre-wrap break-all">- {JSON.stringify(value.oldValue)}</div>
                <div className="text-green-400 whitespace-pre-wrap break-all">+ {JSON.stringify(value.newValue)}</div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

export const DebugInspector = () => {
  const [isVisible, setIsVisible] = useAtom(debugInspectorVisibleAtom);
  const [isExpanded, setIsExpanded] = useAtom(debugInspectorExpandedAtom);
  const [isJournalVisible, setIsJournalVisible] = useAtom(debugInspectorJournalVisibleAtom);
  const [isStateVisible, setIsStateVisible] = useAtom(debugInspectorStateVisibleAtom);
  const [isApiLogExpanded, setIsApiLogExpanded] = useAtom(debugInspectorApiLogExpandedAtom);
  const [isEffectJournalVisible, setIsEffectJournalVisible] = useAtom(debugInspectorEffectJournalVisibleAtom);
  const [isMountJournalVisible, setIsMountJournalVisible] = useAtom(debugInspectorMountJournalVisibleAtom);
  const [isEffectJournalHelpVisible, setIsEffectJournalHelpVisible] =
    React.useState(false);
  const haltedEffects = useAtomValue(haltedEffectsAtom);
  const triggeredEffects = useAtomValue(triggeredEffectsAtom);
  const callCounts = useAtomValue(effectCallCountsAtom);
  const recentCallCounts = useAtomValue(effectRecentCallCountsAtom);
  const mountCounts = useAtomValue(mountCountsAtom);
  const haltedEffectsCount = haltedEffects.size;
  const highestMountCount = Math.max(0, ...Array.from(mountCounts.values()));
  const [mounted, setMounted] = React.useState(false);
  const [copyStatus, setCopyStatus] = React.useState(''); // For "Copied!" message
  const [effectCopyStatus, setEffectCopyStatus] = React.useState('');
  const [mountCopyStatus, setMountCopyStatus] = React.useState('');
  const [stateCopyStatus, setStateCopyStatus] = React.useState('');
  const [eventJournalCopyStatus, setEventJournalCopyStatus] = React.useState('');
  const [diffsCopyStatus, setDiffsCopyStatus] = React.useState('');
  const [isStateDiffVisible, setIsStateDiffVisible] = React.useState(false);
  const [stateHistory, setStateHistory] = React.useState<any[]>([]);
  const [diffs, setDiffs] = React.useState<any[]>([]);
  const [isTokenManuallyExpired, setIsTokenManuallyExpired] = useAtom(isTokenManuallyExpiredAtom);
  const journal = useAtomValue(combinedJournalViewAtom);
  const addJournalEntry = useSetAtom(addEventJournalEntryAtom);
  const clearAndMarkJournal = useSetAtom(clearAndMarkJournalAtom);
  const refreshToken = useSetAtom(clientSideRefreshAtom);
  const expireToken = useSetAtom(expireAccessTokenAtom);
  const checkAuth = useSetAtom(fetchAuthStatusAtom);
  const [authState] = useAtom(authMachineAtom);
  const isAuthActionInProgress = useAtomValue(isAuthActionInProgressAtom);
  const [navState] = useAtom(navigationMachineAtom);
  const journalContainerRef = React.useRef<HTMLDivElement>(null);

  useGuardedEffect(() => {
    if (journalContainerRef.current) {
      journalContainerRef.current.scrollTop = journalContainerRef.current.scrollHeight;
    }
  }, [journal], 'DebugInspector.tsx:autoScrollJournal');

  // Atoms for general state
  const authStatusDetailsValue = useAtomValue(authStatusDetailsAtom);

  // Effect to reset the manual expiry flag whenever auth state changes.
  useGuardedEffect(() => {
    // This effect runs whenever auth state changes, resetting the global atom
    // that tracks manual token expiry. This re-enables the button.
    setIsTokenManuallyExpired(false);
  }, [authStatusDetailsValue, setIsTokenManuallyExpired], 'DebugInspector.tsx:resetManualExpiryFlag');

  const baseDataFromAtom = useAtomValue(baseDataAtom);
  const workerStatusValue = useAtomValue(workerStatusAtom);
  const queryValue = useAtomValue(queryAtom);
  const filtersValue = useAtomValue(filtersAtom);
  const paginationValue = useAtomValue(paginationAtom);
  const sortingValue = useAtomValue(sortingAtom);
  const searchResultValue = useAtomValue(searchResultAtom);
  const selectedUnitsValue = useAtomValue(selectedUnitsAtom);

  // Atoms for redirect logic debugging
  const pathname = usePathname();
  const isAuthenticatedStrictValue = useAtomValue(isAuthenticatedStrictAtom);
  const isAuthenticatedUIValue = useAtomValue(isUserConsideredAuthenticatedForUIAtom);
  const initialAuthCheckCompletedValue = useAtomValue(initialAuthCheckCompletedAtom);
  const requiredSetupRedirectValue = useAtomValue(requiredSetupRedirectAtom);
  const lastKnownPathValue = useAtomValue(lastKnownPathBeforeAuthChangeAtom);
  const redirectRelevantStateValue = useAtomValue(redirectRelevantStateAtom);
  const selectedTimeContextValue = useAtomValue(selectedTimeContextAtom);

  const handleExpireToken = async () => {
    addJournalEntry({
      machine: MachineID.Inspector,
      from: 'user',
      to: 'action',
      event: { type: 'EXPIRE_TOKEN' },
      reason: 'Manual action: Expire Token'
    });
    try {
      // The action atom now handles setting the isTokenManuallyExpiredAtom flag.
      await expireToken();
    } catch (e) {
      console.error('StateInspector: Failed to expire token', e);
    }
  };

  const handleCheckAuth = () => {
    addJournalEntry({
      machine: MachineID.Inspector,
      from: 'user',
      to: 'action',
      event: { type: 'CHECK_AUTH' },
      reason: 'Manual action: Check Auth'
    });
    // The checkAuth atom is now a simple event dispatcher.
    // Loading state is handled by the machine.
    checkAuth();
  };

  const handleRefreshToken = () => {
    addJournalEntry({
      machine: MachineID.Inspector,
      from: 'user',
      to: 'action',
      event: { type: 'REFRESH_TOKEN' },
      reason: 'Manual action: Refresh Token'
    });
    // The refreshToken atom is now a simple event dispatcher.
    // Loading state is handled by the machine.
    refreshToken();
  };
    
  useGuardedEffect(() => {
    setMounted(true);
  }, [], 'DebugInspector.tsx:setMounted');

  useGuardedEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.key === 'k' || e.key === 'K') && (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        setIsVisible(prev => !prev);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [setIsVisible], 'DebugInspector.tsx:keydownListener');

  const baseDataState = baseDataFromAtom.loading ? 'loading' : baseDataFromAtom.error ? 'hasError' : 'hasData';
  const authDerivedState = authStatusDetailsValue.loading ? 'loading' : authStatusDetailsValue.error_code ? 'hasError' : 'hasData';

  const fullState = {
    pathname,
    authStatus: {
      machineState: authState.value,
      derivedState: authDerivedState,
      isAuthenticated: isAuthenticatedUIValue,
      isAuthenticated_STRICT: isAuthenticatedStrictValue,
      isAuthenticated_UNSTABLE: authStatusDetailsValue.isAuthenticated,
      user: authStatusDetailsValue.user,
      expired_access_token_call_refresh: authStatusDetailsValue.expired_access_token_call_refresh,
      error: authStatusDetailsValue.error_code,
    },
    navMachine: {
      state: navState.value,
      context: (({ sideEffect, ...rest}) => rest)(navState.context) // Omit sideEffect for cleaner display
    },
    appContext: {
      selectedTimeContext: selectedTimeContextValue ? {
        ident: selectedTimeContextValue.ident,
        name_when_input: selectedTimeContextValue.name_when_input,
        name_when_query: selectedTimeContextValue.name_when_query,
      } : null,
    },
    baseData: { state: baseDataState, statDefinitionsCount: baseDataState === 'hasData' ? baseDataFromAtom.statDefinitions.length : undefined, externalIdentTypesCount: baseDataState === 'hasData' ? baseDataFromAtom.externalIdentTypes.length : undefined, statbusUsersCount: baseDataState === 'hasData' ? baseDataFromAtom.statbusUsers.length : undefined, timeContextsCount: baseDataState === 'hasData' ? baseDataFromAtom.timeContexts.length : undefined, defaultTimeContextIdent: baseDataState === 'hasData' ? baseDataFromAtom.defaultTimeContext?.ident : undefined, hasStatisticalUnits: baseDataState === 'hasData' ? baseDataFromAtom.hasStatisticalUnits : undefined, error: baseDataState === 'hasError' ? String(baseDataFromAtom.error) : undefined },
    workerStatus: { state: workerStatusValue.loading ? 'loading' : workerStatusValue.error ? 'hasError' : 'hasData', isImporting: workerStatusValue.isImporting, isDerivingUnits: workerStatusValue.isDerivingUnits, isDerivingReports: workerStatusValue.isDerivingReports, loading: workerStatusValue.loading, error: workerStatusValue.error },
    searchAndSelection: {
      searchText: queryValue,
      activeFilterCodes: Object.keys(filtersValue).sort(),
      pagination: paginationValue,
      order: sortingValue,
      selectedUnitsCount: selectedUnitsValue.length,
      searchResult: {
        total: searchResultValue.total,
        loading: searchResultValue.loading,
        error: searchResultValue.error ? String(searchResultValue.error) : null,
      },
    },
    navigationState: { requiredSetupRedirect: requiredSetupRedirectValue, lastKnownPathBeforeAuthChange: lastKnownPathValue },
    redirectRelevantState: redirectRelevantStateValue,
    devToolsState: { isTokenManuallyExpired: isTokenManuallyExpired },
    authApiResponseLog: authState.context.authApiResponseLog,
  };

  // Effect to track state changes and compute diffs
  useGuardedEffect(() => {
    // A stable serialization is important for the dependency array.
    const currentStateJson = JSON.stringify(fullState);
    
    setStateHistory(prevHistory => {
      // Avoid adding duplicate states to history if nothing changed.
      if (prevHistory.length > 0 && JSON.stringify(prevHistory[0]) === currentStateJson) {
        return prevHistory;
      }

      const newState = JSON.parse(currentStateJson); // Deep copy
      const newHistory = [newState, ...prevHistory].slice(0, 5); // Keep last 5 states

      if (newHistory.length > 1) {
        const newDiff = objectDiff(newHistory[1], newHistory[0]);
        if (newDiff) {
          setDiffs(prevDiffs => [{ diff: newDiff, timestamp: new Date() }, ...prevDiffs].slice(0, 5));
        }
      }
      return newHistory;
    });
  }, [JSON.stringify(fullState)], 'DebugInspector.tsx:trackStateHistory');

  const handleCopyState = () => {
    const reportString = JSON.stringify(fullState, null, 2);
    navigator.clipboard.writeText(reportString).then(() => {
      setStateCopyStatus('Copied!');
      setTimeout(() => setStateCopyStatus(''), 2000);
    }).catch(err => {
      console.error('Failed to copy state:', err);
      setStateCopyStatus('Failed');
    });
  };

  const handleCopyDiffs = () => {
    const reportString = diffs.map(entry => 
      `--- ${entry.timestamp.toISOString()} ---\n${formatDiffToString(entry.diff)}`
    ).join('\n');

    navigator.clipboard.writeText(reportString).then(() => {
      setDiffsCopyStatus('Copied!');
      setTimeout(() => setDiffsCopyStatus(''), 2000);
    }).catch(err => {
      console.error('Failed to copy diffs:', err);
      setDiffsCopyStatus('Failed');
    });
  };

  const handleCopyEventJournal = () => {
    const reportString = JSON.stringify(journal, null, 2);
    navigator.clipboard.writeText(reportString).then(() => {
      setEventJournalCopyStatus('Copied!');
      setTimeout(() => setEventJournalCopyStatus(''), 2000);
    }).catch(err => {
      console.error('Failed to copy event journal:', err);
      setEventJournalCopyStatus('Failed');
    });
  };

  const handleCopy = () => {
    // This now copies EVERYTHING for a complete debug report.
    const report = {
      currentState: fullState,
      stateDiffs: diffs,
      eventJournal: journal,
      effectJournal: {
        halted: Array.from(haltedEffects),
        active: Object.fromEntries(callCounts),
      },
      mountJournal: Object.fromEntries(mountCounts),
    };
    const reportString = JSON.stringify(report, null, 2);

    navigator.clipboard.writeText(reportString).then(() => {
      console.log("[DebugInspector] Full Debug Report:", report);
      setCopyStatus('Copied!');
      setTimeout(() => setCopyStatus(''), 2000);
    }).catch(err => {
      console.error('Failed to copy full debug info:', err);
      setCopyStatus('Failed to copy');
    });
  };

  const handleCopyEffectJournal = () => {
    const sortedEffects = Array.from(triggeredEffects).sort((a, b) => {
      const countA = callCounts.get(a) || 0;
      const countB = callCounts.get(b) || 0;
      return countB - countA;
    });

    let reportString = `Effect Journal Report (${new Date().toISOString()})\n`;
    reportString += `Halted Effects: ${haltedEffects.size}\n`;
    reportString += '----------------------------------------\n';
    Array.from(haltedEffects).sort().forEach(effectId => {
      reportString += `- HALTED: ${effectId}\n`;
    });
    reportString += '\nActive Guarded Effects:\n';
    reportString += '----------------------------------------\n';
    reportString += 'Total\tRecent\tEffect ID\n';
    sortedEffects.forEach(effectId => {
      const total = callCounts.get(effectId) || 0;
      const recent = recentCallCounts.get(effectId) || 0;
      reportString += `${total}\t${recent}\t${effectId}\n`;
    });

    navigator.clipboard.writeText(reportString).then(() => {
      setEffectCopyStatus('Copied!');
      setTimeout(() => setEffectCopyStatus(''), 2000);
    }).catch(err => {
      console.error('Failed to copy effect journal:', err);
      setEffectCopyStatus('Failed');
    });
  };

  const handleCopyMountJournal = () => {
    const sortedMounts = Array.from(mountCounts.entries()).sort(([, countA], [, countB]) => countB - countA);
    
    let reportString = `Component Mount Journal Report (${new Date().toISOString()})\n`;
    reportString += '----------------------------------------\n';
    reportString += 'Mounts\tComponent Effect ID\n';
    sortedMounts.forEach(([effectId, count]) => {
      reportString += `${count}\t${effectId}\n`;
    });

    navigator.clipboard.writeText(reportString).then(() => {
      setMountCopyStatus('Copied!');
      setTimeout(() => setMountCopyStatus(''), 2000);
    }).catch(err => {
      console.error('Failed to copy mount journal:', err);
      setMountCopyStatus('Failed');
    });
  };

  const handleClearJournal = () => {
    clearAndMarkJournal();
    setDiffs([]);
    setStateHistory([]);
  };

  const getSimpleStatus = (s: any) => s.state === 'loading' ? 'Loading' : s.state === 'hasError' ? 'Error' : 'OK';
  const getWorkerSummary = (d: any) => !d ? 'N/A' : d.isImporting ? 'Importing' : d.isDerivingUnits ? 'Deriving Units' : d.isDerivingReports ? 'Deriving Reports' : 'Idle';

  if (!mounted) {
    // During SSR or initial client render, we cannot know if the inspector should be visible
    // because its state is in localStorage. To prevent a hydration mismatch, render nothing,
    // which matches the server's behavior (where the atom's default value is `false`).
    return null;
  }
  if (!isVisible) return null;

  const stateToDisplay = fullState;

  return (
    <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white rounded-lg text-xs max-w-md max-h-[80vh] overflow-auto z-[9999]">
      <div className="sticky top-0 z-10 bg-black bg-opacity-80 p-2 flex justify-between items-center">
        <span onClick={() => setIsExpanded(!isExpanded)} className="cursor-pointer font-bold">Debug Inspector {isExpanded ? '▼' : '▶'}</span>
        <div className="flex items-center space-x-1">
          <button
            onClick={handleCopy}
            className="px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded text-xs"
            title="Copy current state and saga to clipboard"
          >
            {copyStatus || 'Copy'}
          </button>
          <button
            onClick={handleClearJournal}
            className="px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded text-xs"
            title="Clear the event journal"
          >
            Clear Journal
          </button>
        </div>
      </div>
      {!isExpanded && (
        <div className="px-2 pt-1 pb-2">
          <span>Auth: {getSimpleStatus(stateToDisplay.authStatus)}</span> | <span>Base: {getSimpleStatus(stateToDisplay.baseData)}</span> | <span>Worker: {stateToDisplay.workerStatus?.loading ? 'Loading' : stateToDisplay.workerStatus?.error ? 'Error' : getWorkerSummary(stateToDisplay.workerStatus)}</span>
        </div>
      )}
      {isExpanded && (
        <div className="p-2 space-y-2">
          <div className="flex items-center space-x-1">
            <strong>Manage Auth:</strong>
            <button
              onClick={handleExpireToken}
              disabled={isAuthActionInProgress || isTokenManuallyExpired}
              className={`px-2 py-1 rounded text-xs ${
                isTokenManuallyExpired || isAuthActionInProgress
                  ? 'bg-gray-500 text-gray-300 cursor-not-allowed'
                  : 'bg-yellow-600 hover:bg-yellow-500'
              }`}
              title="Expire the current JWT access token, forcing a refresh on the next action"
            >
              {isTokenManuallyExpired ? 'Token Expired' : 'Expire Token'}
            </button>
            <button
              onClick={handleRefreshToken}
              disabled={isAuthActionInProgress}
              className="px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded text-xs disabled:opacity-50"
              title="Trigger a client-side token refresh"
            >
              {authState.matches({ idle_authenticated: 'background_refreshing' }) || authState.matches('initial_refreshing') ? 'Refreshing...' : 'Refresh Token'}
            </button>
            <button
              onClick={handleCheckAuth}
              disabled={isAuthActionInProgress}
              className="px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded text-xs disabled:opacity-50"
              title="Trigger a server-side auth status check"
            >
              {authState.matches('checking') || authState.matches({ idle_authenticated: 'revalidating' }) ? 'Checking...' : 'Check Auth'}
            </button>
          </div>

          <div>
            <div className="flex items-center space-x-2">
              <strong onClick={() => setIsStateDiffVisible(v => !v)} className="cursor-pointer">State Diffs (last 5) {isStateDiffVisible ? '▼' : '▶'}</strong>
              <button onClick={handleCopyDiffs} className="px-2 py-0.5 bg-gray-700 hover:bg-gray-600 rounded text-xs">
                {diffsCopyStatus || 'Copy'}
              </button>
            </div>
            {isStateDiffVisible && (
              <div className="pl-4 mt-1 space-y-2 max-h-96 overflow-y-auto border border-gray-600 rounded p-1 bg-black/20">
                {diffs.length > 0 ? diffs.map((entry, index) => (
                  <div key={index} className="border-b border-gray-700 pb-2 mb-2 last:border-b-0">
                    <div className="text-gray-400 font-bold mb-1">{entry.timestamp.toLocaleTimeString()}.{String(entry.timestamp.getMilliseconds()).padStart(3, '0')}</div>
                    <StateDiff diff={entry.diff} />
                  </div>
                )) : <div className="text-gray-500 italic">No state changes detected yet.</div>}
              </div>
            )}
          </div>

          <div>
            <div className="flex items-center space-x-2">
              <strong onClick={() => setIsJournalVisible((v: boolean) => !v)} className="cursor-pointer">
                Event Journal {isJournalVisible ? '▼' : '▶'}
              </strong>
              <button onClick={handleCopyEventJournal} className="px-2 py-0.5 bg-gray-700 hover:bg-gray-600 rounded text-xs">
                {eventJournalCopyStatus || 'Copy'}
              </button>
              
              {isGuardingEnabled ? (
                <>
                  <span className="text-gray-500">|</span>
                  <strong onClick={() => setIsEffectJournalVisible((v: boolean) => !v)} className="cursor-pointer flex items-center">
                    Effect
                    {haltedEffectsCount > 0 ? (
                      <span className="ml-1 text-red-400">({haltedEffectsCount} ⛔)</span>
                    ) : (
                      <span className="ml-1 text-green-500">(✅)</span>
                    )}
                    {isEffectJournalVisible ? '▼' : '▶'}
                  </strong>
                  
                  <span className="text-gray-500">|</span>
                  <strong onClick={() => setIsMountJournalVisible((v: boolean) => !v)} className="cursor-pointer flex items-center">
                    Mount
                    {highestMountCount > 5 ? (
                      <span className="ml-1 text-yellow-400">({highestMountCount} ⚠️)</span>
                    ) : (
                      <span className="ml-1 text-green-500">(✅)</span>
                    )}
                     {isMountJournalVisible ? '▼' : '▶'}
                  </strong>
                </>
              ) : (
                <span className="text-gray-500 italic">(Guards Disabled)</span>
              )}

              <span
                onClick={() => setIsEffectJournalHelpVisible((v: boolean) => !v)}
                className="ml-1 px-1.5 py-0 bg-gray-600 rounded-full text-xs cursor-pointer hover:bg-gray-500"
                title="Click for help on how to enable the Effect Guard"
              >
                ?
              </span>
            </div>
            
            {isEffectJournalHelpVisible && (
              <div className="pl-4 mt-1 text-xs text-gray-400 border border-gray-600 rounded p-2 bg-black/20 space-y-2">
                <p>The Effect Guard is a development-only tool to find infinite loops.</p>
                <div>
                  <strong className="font-bold">For Local Development:</strong>
                  <p className="mt-1">
                    1. Add the following to your{' '}
                    <code className="bg-gray-700 p-1 rounded">.env.local</code> file:
                  </p>
                  <pre className="mt-1 p-2 bg-gray-800 rounded">
                    <code>NEXT_PUBLIC_ENABLE_EFFECT_GUARD=true</code>
                  </pre>
                  <p className="mt-1">2. Restart the Next.js development server.</p>
                </div>
                <div>
                  <strong className="font-bold">For a Deployed Environment:</strong>
                  <p className="mt-1">
                    1. Set the environment variable:
                  </p>
                  <pre className="mt-1 p-2 bg-gray-800 rounded">
                    <code>NEXT_PUBLIC_ENABLE_EFFECT_GUARD=true</code>
                  </pre>
                  <p className="mt-1">
                    2. Restart the application:
                  </p>
                  <pre className="mt-1 p-2 bg-gray-800 rounded">
                    <code>./devops/manage-statbus.sh restart app</code>
                  </pre>
                </div>
              </div>
            )}

            {isJournalVisible && (
              <div ref={journalContainerRef} className="pl-4 mt-1 space-y-1 font-mono text-xs max-h-48 overflow-y-auto border border-gray-600 rounded p-1 bg-black/20">
                {journal.length > 0 ? (
                  journal.map((entry, index) => {
                    let machineColor = 'text-cyan-400';
                    if (entry.machine === MachineID.System) machineColor = 'text-purple-400';
                    if (entry.machine === MachineID.Inspector) machineColor = 'text-orange-400';
                    return (
                      <div key={`${entry.timestamp_epoch}-${index}`}>
                        <span className="text-gray-400">
                          {new Date(entry.timestamp_epoch).toLocaleTimeString()}.{String(entry.timestamp_epoch % 1000).padStart(3, '0')}
                        </span>
                        <span className={`font-bold ${machineColor}`}> [{entry.machine.toUpperCase()}] </span>
                        <span className="text-yellow-400">{JSON.stringify(entry.from)}</span>
                        <span className="text-gray-400"> → </span>
                        <span className="text-green-400">{JSON.stringify(entry.to)}</span>
                        {entry.event.type !== 'unknown' && <span className="text-gray-500"> on {entry.event.type}</span>}
                      </div>
                    );
                  })
                ) : (
                  <div className="text-gray-500 italic">No events recorded.</div>
                )}
              </div>
            )}

            {isEffectJournalVisible && isGuardingEnabled && (
              <div className="pl-4 mt-1 space-y-2 font-mono text-xs max-h-48 overflow-y-auto border border-gray-600 rounded p-1 bg-black/20">
                <div className="sticky top-0 z-10 flex items-center justify-between bg-black/80 py-1 backdrop-blur-sm">
                  <strong>Effect Log</strong>
                  <button onClick={handleCopyEffectJournal} className="px-2 py-0.5 bg-gray-700 hover:bg-gray-600 rounded text-xs">
                    {effectCopyStatus || 'Copy'}
                  </button>
                </div>
                <div>
                  <strong>Halted ({haltedEffects.size}):</strong>
                  {haltedEffects.size > 0 ? (
                    Array.from(haltedEffects).sort().map((effectId) => (
                      <div key={effectId} className="text-red-400 ml-2">
                        {effectId}
                      </div>
                    ))
                  ) : (
                    <div className="text-gray-500 italic ml-2">None</div>
                  )}
                </div>
                <div>
                  <strong>Active ({triggeredEffects.size}):</strong>
                  {triggeredEffects.size > 0 ? (
                    <div className="ml-2 mt-1 space-y-1">
                      <div className="flex font-bold text-gray-400 border-b border-gray-600 pb-1">
                        <div className="flex-grow pr-2">Effect ID</div>
                        <div className="w-10 text-right pr-2">Total</div>
                        <div className="w-28 text-right">
                          Last {LOOP_DETECTION_WINDOW_MS}ms
                        </div>
                      </div>
                      {Array.from(triggeredEffects)
                        .sort((a, b) => {
                          const countA = callCounts.get(a) || 0;
                          const countB = callCounts.get(b) || 0;
                          return countB - countA;
                        })
                        .map((effectId) => {
                          const count = callCounts.get(effectId) || 0;
                          const recentCount =
                            recentCallCounts.get(effectId) || 0;
                          return (
                            <div
                              key={effectId}
                              className="flex text-cyan-400 items-center"
                            >
                              <div
                                className="flex-grow truncate pr-2"
                                title={effectId}
                              >
                                {effectId}
                              </div>
                              <div className="w-10 text-right pr-2">
                                {count}
                              </div>
                              <div className="w-28 text-right">
                                {recentCount}
                              </div>
                            </div>
                          );
                        })}
                    </div>
                  ) : (
                    <div className="text-gray-500 italic ml-2">None</div>
                  )}
                </div>
              </div>
            )}
            
            {isMountJournalVisible && isGuardingEnabled && (
              <div className="pl-4 mt-1 space-y-2 font-mono text-xs max-h-48 overflow-y-auto border border-gray-600 rounded p-1 bg-black/20">
                <div className="sticky top-0 z-10 flex items-center justify-between bg-black/80 py-1 backdrop-blur-sm">
                  <strong>Component Mount Log</strong>
                  <button onClick={handleCopyMountJournal} className="px-2 py-0.5 bg-gray-700 hover:bg-gray-600 rounded text-xs">
                    {mountCopyStatus || 'Copy'}
                  </button>
                </div>
                <div>
                  {mountCounts.size > 0 ? (
                    <div className="ml-2 mt-1 space-y-1">
                      <div className="flex font-bold text-gray-400 border-b border-gray-600 pb-1">
                        <div className="flex-grow pr-2">Component Effect ID</div>
                        <div className="w-16 text-right">Mounts</div>
                      </div>
                      {Array.from(mountCounts.entries())
                        .sort(([, countA], [, countB]) => countB - countA)
                        .map(([effectId, count]) => (
                          <div
                            key={effectId}
                            className={`flex items-center ${
                              count > 5 ? 'text-yellow-400' : 'text-cyan-400'
                            }`}
                          >
                            <div
                              className="flex-grow truncate pr-2"
                              title={effectId}
                            >
                              {effectId}
                            </div>
                            <div className="w-16 text-right font-bold">
                              {count}
                            </div>
                          </div>
                        ))}
                    </div>
                  ) : (
                    <div className="text-gray-500 italic ml-2">No components have mounted yet.</div>
                  )}
                </div>
              </div>
            )}
          </div>

          <div>
            <div className="flex items-center space-x-2">
              <strong onClick={() => setIsStateVisible(v => !v)} className="cursor-pointer">Current State: {isStateVisible ? '▼' : '▶'}</strong>
              <button onClick={handleCopyState} className="px-2 py-0.5 bg-gray-700 hover:bg-gray-600 rounded text-xs">
                {stateCopyStatus || 'Copy'}
              </button>
            </div>
            {isStateVisible && (
              <div className="pl-4 mt-1 space-y-2 max-h-96 overflow-y-auto border border-gray-600 rounded p-1 bg-black/20">
              <div>
                <strong>State Machines:</strong>
                <div className="pl-4 mt-1 space-y-1">
                  <div><strong>Auth:</strong> {JSON.stringify(stateToDisplay.authStatus?.machineState)}</div>
                  <div><strong>Nav:</strong> {JSON.stringify(stateToDisplay.navMachine?.state)}</div>
                  {stateToDisplay.navMachine?.context && (
                    <div className="pl-4 font-mono text-xs">
                      {Object.entries(stateToDisplay.navMachine.context).map(([key, value]) => (
                        <div key={key}>- {key}: {JSON.stringify(value)}</div>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              <div>
                <strong>Auth Details:</strong>
                <div className="pl-4 mt-1 space-y-1">
                  {stateToDisplay.authStatus?.derivedState === 'hasData' ? (
                    <>
                      <div><strong>Authenticated (UI):</strong> {stateToDisplay.authStatus.isAuthenticated ? 'Yes' : 'No'}</div>
                      <div><strong>Authenticated (Strict/Data):</strong> {stateToDisplay.authStatus.isAuthenticated_STRICT ? 'Yes' : 'No'}</div>
                      <div><strong>Authenticated (Unstable):</strong> {stateToDisplay.authStatus.isAuthenticated_UNSTABLE ? 'Yes' : 'No'}</div>
                      <div><strong>User:</strong> {stateToDisplay.authStatus.user?.email || 'None'}</div>
                      <div><strong>UID:</strong> {stateToDisplay.authStatus.user?.uid || 'N/A'}</div>
                      <div><strong>Role:</strong> {stateToDisplay.authStatus.user?.role || 'N/A'}</div>
                      <div><strong>Statbus Role:</strong> {stateToDisplay.authStatus.user?.statbus_role || 'N/A'}</div>
                      <div><strong>Refresh Needed:</strong> {stateToDisplay.authStatus.expired_access_token_call_refresh ? 'Yes' : 'No'}</div>
                    </>
                  ) : (
                    <>
                      <div><strong>Derived State:</strong> {stateToDisplay.authStatus?.derivedState}</div>
                      {stateToDisplay.authStatus?.derivedState === 'hasError' && <div><strong>Error:</strong> {String(stateToDisplay.authStatus.error)}</div>}
                    </>
                  )}
                </div>
              </div>

              <div>
                <strong>App Context:</strong>
                <div className="pl-4 mt-1 space-y-1">
                  <div><strong>Time Context:</strong> {(
                      () => {
                        const tc = stateToDisplay.appContext?.selectedTimeContext;
                        if (!tc) return 'None';
                        const displayName = tc.name_when_input || tc.name_when_query;
                        return `${displayName} (${tc.ident})`;
                      }
                    )()}</div>
                </div>
              </div>

              <div>
                <strong>Base Data Status:</strong> {stateToDisplay.baseData?.state}
                <div className="pl-4 mt-1 space-y-1">
                  {stateToDisplay.baseData?.state === 'hasData' && (
                    <>
                      <div><strong>Stat Definitions:</strong> {stateToDisplay.baseData.statDefinitionsCount}</div>
                      <div><strong>External Ident Types:</strong> {stateToDisplay.baseData.externalIdentTypesCount}</div>
                      <div><strong>Statbus Users:</strong> {stateToDisplay.baseData.statbusUsersCount}</div>
                      <div><strong>Time Contexts:</strong> {stateToDisplay.baseData.timeContextsCount}</div>
                      <div><strong>Default Time Context:</strong> {stateToDisplay.baseData.defaultTimeContextIdent || 'None'}</div>
                      <div><strong>Has Statistical Units:</strong> {stateToDisplay.baseData.hasStatisticalUnits ? 'Yes' : 'No'}</div>
                    </>
                  )}
                  {stateToDisplay.baseData?.state === 'hasError' && <div><strong>Error:</strong> {String(stateToDisplay.baseData.error)}</div>}
                </div>
              </div>

              <div>
                <strong>Search & Selection State:</strong>
                <div className="pl-4 mt-1 space-y-1">
                  <div><strong>Search Text:</strong> {stateToDisplay.searchAndSelection?.searchText || 'None'}</div>
                  <div><strong>Active Filters:</strong> {stateToDisplay.searchAndSelection?.activeFilterCodes?.join(', ') || 'None'}</div>
                  <div><strong>Pagination:</strong> Page {stateToDisplay.searchAndSelection?.pagination?.page}, Size {stateToDisplay.searchAndSelection?.pagination?.pageSize}</div>
                  <div><strong>Order:</strong> {stateToDisplay.searchAndSelection?.order?.field} {stateToDisplay.searchAndSelection?.order?.direction}</div>
                  <div><strong>Selected Units:</strong> {stateToDisplay.searchAndSelection?.selectedUnitsCount}</div>
                  <div><strong>Search Result:</strong> Total {stateToDisplay.searchAndSelection?.searchResult?.total ?? 'N/A'}, Loading: {stateToDisplay.searchAndSelection?.searchResult?.loading ? 'Yes' : 'No'}</div>
                  {stateToDisplay.searchAndSelection?.searchResult?.error && <div><strong>Search Error:</strong> {stateToDisplay.searchAndSelection.searchResult.error}</div>}
                </div>
              </div>

              <div>
                <strong>Worker Status:</strong> {stateToDisplay.workerStatus?.loading ? 'Loading' : stateToDisplay.workerStatus?.error ? 'Error' : 'OK'}
                <div className="pl-4 mt-1 space-y-1">
                  {stateToDisplay.workerStatus && !stateToDisplay.workerStatus.loading && !stateToDisplay.workerStatus.error && (
                    <>
                      <div><strong>Importing:</strong> {stateToDisplay.workerStatus.isImporting === null ? 'N/A' : stateToDisplay.workerStatus.isImporting ? 'Yes' : 'No'}</div>
                      <div><strong>Deriving Units:</strong> {stateToDisplay.workerStatus.isDerivingUnits === null ? 'N/A' : stateToDisplay.workerStatus.isDerivingUnits ? 'Yes' : 'No'}</div>
                      <div><strong>Deriving Reports:</strong> {stateToDisplay.workerStatus.isDerivingReports === null ? 'N/A' : stateToDisplay.workerStatus.isDerivingReports ? 'Yes' : 'No'}</div>
                    </>
                  )}
                  {stateToDisplay.workerStatus?.error && <div><strong>Error:</strong> {stateToDisplay.workerStatus.error}</div>}
                </div>
              </div>

              <div>
                <strong>Navigation & Redirect Debugging:</strong>
                <div className="pl-4 mt-1 space-y-1">
                  <div><strong>Initial Auth Check Completed:</strong> {stateToDisplay.redirectRelevantState?.initialAuthCheckCompleted ? 'Yes' : 'No'}</div>
                  <hr className="my-1 border-gray-500" />
                  <div><strong>Pathname:</strong> {stateToDisplay.pathname}</div>
                  <div><strong>Active Redirect Target:</strong> {stateToDisplay.navigationState?.requiredSetupRedirect || 'None'}</div>
                  <div><strong>Required Setup Redirect:</strong> {stateToDisplay.navigationState?.requiredSetupRedirect || 'None'}</div>
                  <div><strong>Last Known Path (pre-auth):</strong> {stateToDisplay.navigationState?.lastKnownPathBeforeAuthChange || 'None'}</div>
                  <hr className="my-1 border-gray-500" />
                  <div><strong>Auth Check Done:</strong> {stateToDisplay.redirectRelevantState?.authCheckDone ? 'Yes' : 'No'}</div>
                  <div><strong>REST Client Ready:</strong> {stateToDisplay.redirectRelevantState?.isRestClientReady ? 'Yes' : 'No'}</div>
                  <div><strong>Activity Standard:</strong> {stateToDisplay.redirectRelevantState?.activityStandard === null ? 'Null' : JSON.stringify(stateToDisplay.redirectRelevantState?.activityStandard)}</div>
                  <div><strong>Number of Regions:</strong> {stateToDisplay.redirectRelevantState?.numberOfRegions === null ? 'Null/Loading' : stateToDisplay.redirectRelevantState?.numberOfRegions}</div>
                  <div><strong>BaseData - Has Statistical Units:</strong> {stateToDisplay.redirectRelevantState?.baseDataHasStatisticalUnits === 'BaseDataNotLoaded' ? 'BaseDataNotLoaded' : (stateToDisplay.redirectRelevantState?.baseDataHasStatisticalUnits ? 'Yes' : 'No')}</div>
                  <div><strong>BaseData - Stat Definitions Count:</strong> {stateToDisplay.redirectRelevantState?.baseDataStatDefinitionsLength}</div>
                </div>
              </div>
              <div>
                <strong>DevTools State:</strong>
                <div className="pl-4 mt-1 space-y-1">
                  <div><strong>Token Manually Expired:</strong> {stateToDisplay.devToolsState?.isTokenManuallyExpired ? 'Yes' : 'No'}</div>
                </div>
              </div>
              {stateToDisplay.authApiResponseLog && Object.keys(stateToDisplay.authApiResponseLog).length > 0 && (
                <div>
                  <strong onClick={() => setIsApiLogExpanded(v => !v)} className="cursor-pointer">
                    Auth API Response Log ({Object.keys(stateToDisplay.authApiResponseLog).length}) {isApiLogExpanded ? '▼' : '▶'}
                  </strong>
                  {isApiLogExpanded && (
                    <div className="pl-4 mt-1 space-y-2 font-mono text-xs max-h-48 overflow-y-auto border border-gray-600 rounded p-1 bg-black/20">
                      {Object.entries(stateToDisplay.authApiResponseLog)
                        .sort(([keyA], [keyB]) => Number(keyB) - Number(keyA)) // Newest first
                        .map(([timestamp, logEntry]: [string, any]) => (
                          <div key={timestamp} className="border-b border-gray-700 pb-1 mb-1 last:border-b-0">
                            <p className="text-yellow-400 font-bold">
                              {`[${new Date(Number(timestamp)).toLocaleTimeString()}.${String(Number(timestamp) % 1000).padStart(3, '0')}] ${logEntry.type.replace(/_/g, ' ').toUpperCase()}`}
                            </p>
                            <pre className="whitespace-pre-wrap break-all">{JSON.stringify(logEntry.response, null, 2)}</pre>
                          </div>
                        ))
                      }
                    </div>
                  )}
                </div>
              )}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
