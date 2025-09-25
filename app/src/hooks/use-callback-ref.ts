import * as React from "react";

/**
 * @see https://github.com/radix-ui/primitives/blob/main/packages/react/use-callback-ref/src/useCallbackRef.tsx
 */

/**
 * A custom hook that converts a callback to a ref to avoid triggering re-renders when passed as a
 * prop or avoid re-executing effects when passed as a dependency
 */
function useCallbackRef<T extends (...args: never[]) => unknown>(
  callback: T | undefined,
): T {
  const callbackRef = React.useRef(callback);

  // This effect is intentionally NOT converted to useGuardedEffect.
  // The purpose of this hook is to safely handle frequently changing callback
  // references. Its internal effect is expected to run often and represents
  // a "leaf" in the render tree, not a source of loops. Guarding it would
  // create excessive noise in the Effect Journal without providing actionable
  // intelligence about bugs.
  React.useEffect(() => {
    // This effect synchronizes the ref with the latest callback.
    // It runs only when the callback function reference changes.
    callbackRef.current = callback;
  }, [callback]);

  // https://github.com/facebook/react/issues/19240
  return React.useMemo(
    () => ((...args) => callbackRef.current?.(...args)) as T,
    [],
  );
}

export { useCallbackRef };
