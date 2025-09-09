"use client";

import { atom, useSetAtom } from 'jotai';
import { useEffect, useRef } from 'react';
import { useAtomValue } from 'jotai';

export const isGuardingEnabled = process.env.NEXT_PUBLIC_ENABLE_EFFECT_GUARD === 'true';

// State atoms
export const effectCallCountsAtom = atom<Map<string, number>>(new Map());
export const effectRecentCallCountsAtom = atom<Map<string, number>>(new Map());
export const mountCountsAtom = atom<Map<string, number>>(new Map());
export const triggeredEffectsAtom = atom<Set<string>>(new Set<string>());
export const haltedEffectsAtom = atom<Set<string>>(new Set<string>());

export const LOOP_DETECTION_WINDOW_MS = 2000;
const LOOP_DETECTION_THRESHOLD = 100;

export const useGuardedEffect = (
  effect: React.EffectCallback,
  deps: React.DependencyList,
  effectId: string
) => {
  const setCallCounts = useSetAtom(effectCallCountsAtom);
  const setRecentCallCounts = useSetAtom(effectRecentCallCountsAtom);
  const setMountCounts = useSetAtom(mountCountsAtom);
  const setTriggeredEffects = useSetAtom(triggeredEffectsAtom);
  const setHaltedEffects = useSetAtom(haltedEffectsAtom);
  const haltedEffects = useAtomValue(haltedEffectsAtom);

  // This effect hook journals the component's lifecycle (mount/unmount).
  // It is the key to detecting re-mount loops, which the original guard could not.
  useEffect(() => {
    if (!isGuardingEnabled) return;

    setMountCounts(prev => new Map(prev).set(effectId, (prev.get(effectId) || 0) + 1));
    
    // The return function from a useEffect with an empty dependency array is the
    // perfect place to log an unmount event, though we don't currently need to.
    return () => {};
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [effectId, setMountCounts]);

  // This is the main effect logic that runs the user's provided effect.
  useEffect(() => {
    if (!isGuardingEnabled) {
      return effect();
    }

    if (haltedEffects.has(effectId)) {
      return;
    }

    setTriggeredEffects((prev: Set<string>) => new Set(prev).add(effectId));

    setCallCounts(prev => new Map(prev).set(effectId, (prev.get(effectId) || 0) + 1));

    setRecentCallCounts(prev => {
      const newMap = new Map(prev);
      const newCount = (newMap.get(effectId) || 0) + 1;
      newMap.set(effectId, newCount);
      
      if (newCount > LOOP_DETECTION_THRESHOLD) {
        console.error(
          `[Effect Guard] Halted effect "${effectId}" due to potential infinite loop (${newCount} calls in ${LOOP_DETECTION_WINDOW_MS}ms).`
        );
        setHaltedEffects((prevHalted: Set<string>) => new Set(prevHalted).add(effectId));
      }
      return newMap;
    });

    const timeoutId = setTimeout(() => {
      setRecentCallCounts(prev => {
        const newMap = new Map(prev);
        const currentCount = newMap.get(effectId) || 0;
        if (currentCount > 0) {
          newMap.set(effectId, currentCount - 1);
        }
        return newMap;
      });
    }, LOOP_DETECTION_WINDOW_MS);
    
    const cleanup = effect();

    return () => {
      clearTimeout(timeoutId);
      if (cleanup) {
        cleanup();
      }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
};
