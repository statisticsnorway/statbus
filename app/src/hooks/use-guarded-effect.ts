import { atom, useAtom, useSetAtom } from 'jotai'
import { useEffect, useRef } from 'react'

// Check the feature flag once at the module level. This ensures zero runtime
// overhead for the disabled case and is safe because env vars do not change
// during the application's lifecycle.
export const isGuardingEnabled =
  process.env.NEXT_PUBLIC_ENABLE_EFFECT_GUARD === 'true'

// --- Common definitions used only by the enabled hook ---
// This is exported for the StateInspector to display halted effects.
export const haltedEffectsAtom = atom<ReadonlySet<string>>(new Set<string>())
// This is exported for the StateInspector to display triggered effects.
export const triggeredEffectsAtom = atom<ReadonlySet<string>>(new Set<string>())
// This is exported for the StateInspector to display call counts.
export const effectCallCountsAtom = atom<ReadonlyMap<string, number>>(new Map())
// This is exported for the StateInspector to display recent call counts.
export const effectRecentCallCountsAtom = atom<ReadonlyMap<string, number>>(
  new Map(),
)
let unidentifiedEffectCounter = 0
const LOOP_DETECTION_THRESHOLD = 100 // More than 100 calls...
export const LOOP_DETECTION_WINDOW_MS = 500 // ...within 500ms is considered a loop.

/**
 * A best-effort utility to find the call site of the guarded effect.
 * It works by creating an error and parsing the stack trace.
 * NOTE: Stack trace formats are not standardized and may vary by browser.
 */
function getCallerInfo(): { info: string; stack?: string } {
  try {
    const err = new Error();
    const stack = err.stack || '';
    const lines = stack.split('\n');
    const hookFileName = 'use-guarded-effect.ts';

    // Find the first line in the stack trace that is NOT from our hook file.
    for (const line of lines) {
      if (line.includes(hookFileName) || line.trim().startsWith('Error')) {
        continue;
      }

      const callerLine = line.trim();
      const match = callerLine.match(/\(([^)]+)\)/);
      if (match && match[1]) {
        return { info: match[1].replace('webpack-internal:///.', ''), stack };
      }
      const atMatch = callerLine.match(/at (.*)/);
      if (atMatch && atMatch[1]) {
        return { info: atMatch[1], stack };
      }
      return { info: callerLine, stack };
    }
    
    return { info: '(Could not automatically determine caller)', stack };
  } catch (e) {
    return { info: '(Error getting caller information)' };
  }
}

// --- Hook Implementations ---

/** The full-featured implementation of the hook, with loop detection. */
function useGuardedEffectEnabled(
  effect: React.EffectCallback,
  deps: React.DependencyList,
  identifier?: string,
) {
  const idRef = useRef<string | undefined>(undefined)
  const [haltedEffects, setHaltedEffects] = useAtom(haltedEffectsAtom)
  const setTriggeredEffects = useSetAtom(triggeredEffectsAtom)
  const setCallCounts = useSetAtom(effectCallCountsAtom)
  const setRecentCallCounts = useSetAtom(effectRecentCallCountsAtom)
  const timestampsRef = useRef<number[]>([])
  const effectRef = useRef(effect)

  useEffect(() => {
    effectRef.current = effect
  }, [effect])

  if (!identifier && !idRef.current) {
    const { info: callerInfo } = getCallerInfo();
    // Append a counter to ensure uniqueness even if multiple effects are on the same line
    idRef.current = `${callerInfo} #${unidentifiedEffectCounter++}`;
  }
  const finalIdentifier = identifier || idRef.current!

  // Effect to register/unregister this guarded effect instance for display.
  useEffect(() => {
    setTriggeredEffects((prev) => {
      const newSet = new Set(prev)
      newSet.add(finalIdentifier)
      return newSet
    })
    return () => {
      setTriggeredEffects((prev) => {
        const newSet = new Set(prev)
        newSet.delete(finalIdentifier)
        return newSet
      })
      // The total call count is intentionally NOT cleared on unmount. This makes
      // the "total" count more intuitive in a dev environment with fast refresh,
      // as it will reflect all calls since the page loaded, preventing the
      // race condition where "recent" could appear larger than "total".
      setRecentCallCounts((prev) => {
        const newMap = new Map(prev)
        newMap.delete(finalIdentifier)
        return newMap
      })
    }
  }, [finalIdentifier, setTriggeredEffects, setCallCounts, setRecentCallCounts])

  useEffect(
    () => {
      if (haltedEffects.has(finalIdentifier)) return

      // Increment call count for this effect instance.
      setCallCounts((prev) => {
        const newMap = new Map(prev)
        newMap.set(finalIdentifier, (newMap.get(finalIdentifier) || 0) + 1)
        return newMap
      })

      const now = Date.now()
      const { current: timestamps } = timestampsRef
      timestamps.push(now)
      const recentTimestamps = timestamps.filter(
        (ts) => now - ts <= LOOP_DETECTION_WINDOW_MS,
      )
      timestampsRef.current = recentTimestamps

      setRecentCallCounts((prev) => {
        const newMap = new Map(prev)
        newMap.set(finalIdentifier, recentTimestamps.length)
        return newMap
      })

      if (recentTimestamps.length > LOOP_DETECTION_THRESHOLD) {
        const { info: callerInfo, stack } = getCallerInfo()
        // eslint-disable-next-line no-console
        console.error(
          `HALTED: Infinite loop detected in effect identified as "${finalIdentifier}".\n` +
            `Probable source: ${callerInfo}\n` +
            `The effect was called ${recentTimestamps.length} times in the last ${LOOP_DETECTION_WINDOW_MS}ms.`,
        )
        // In production builds, the caller info might be cryptic. Log the full stack
        // to give the developer more context to trace the origin of the effect.
        if (stack) {
          // eslint-disable-next-line no-console
          console.log("Full stack trace for debugging:", stack);
        }
        setHaltedEffects((prev: ReadonlySet<string>) => {
          const newHalted = new Set(prev)
          newHalted.add(finalIdentifier)
          return newHalted
        })
        return
      }

      const cleanup = effectRef.current()
      return cleanup
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [...deps, finalIdentifier, haltedEffects, setHaltedEffects, setRecentCallCounts],
  )
}

/** The lightweight, pass-through implementation for when the guard is disabled. */
function useGuardedEffectDisabled(
  effect: React.EffectCallback,
  deps: React.DependencyList,
) {
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(effect, deps)
}

/**
 * A development-only wrapper around `useEffect` that detects and halts
 * potential infinite loops. It is designed to be a drop-in replacement
 * for `useEffect` during debugging sessions.
 *
 * The guard can be globally enabled by setting `NEXT_PUBLIC_ENABLE_EFFECT_GUARD=true`
 * in your `.env.local` file. When disabled, this hook has zero performance
 * overhead and behaves exactly like a standard `useEffect`.
 *
 * @param effect Effect callback, same as `useEffect`.
 * @param deps Dependency array, same as `useEffect`.
 * @param identifier An optional unique string to identify the effect. If not
 *   provided, the hook will attempt to automatically determine the call site.
 */
export const useGuardedEffect = isGuardingEnabled
  ? useGuardedEffectEnabled
  : useGuardedEffectDisabled
