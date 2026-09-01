import { useSyncExternalStore } from "react";

const subscribe = () => () => {};

/**
 * Reports false for the server render and true after client hydration without
 * scheduling a component-local state update from an effect.
 */
export function useClientReady(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => true,
    () => false
  );
}
