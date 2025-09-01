import * as React from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

import { useCallbackRef } from "@/hooks/use-callback-ref";

export function useDebouncedCallback<T extends (...args: never[]) => unknown>(
  callback: T,
  delay: number,
) {
  const handleCallback = useCallbackRef(callback);
  const debounceTimerRef = React.useRef(0);
  useGuardedEffect(
    () => () => window.clearTimeout(debounceTimerRef.current),
    [],
    'use-debounced-callback.ts:clearTimeoutOnUnmount'
  );

  const setValue = React.useCallback(
    (...args: Parameters<T>) => {
      window.clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = window.setTimeout(
        () => handleCallback(...args),
        delay,
      );
    },
    [handleCallback, delay],
  );

  return setValue;
}
