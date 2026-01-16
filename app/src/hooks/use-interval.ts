import { useRef, useEffect } from 'react';

/**
 * Custom hook for setting up intervals with automatic cleanup
 * Based on Dan Abramov's useInterval pattern: https://overreacted.io/making-setinterval-declarative-with-react-hooks/
 * 
 * @param callback - Function to call on each interval
 * @param delay - Delay in milliseconds, or null to pause the interval
 */
export function useInterval(callback: () => void, delay: number | null) {
  const savedCallback = useRef<() => void>(callback);

  // Remember the latest callback
  useEffect(() => {
    savedCallback.current = callback;
  }, [callback]);

  // Set up the interval
  useEffect(() => {
    function tick() {
      if (savedCallback.current) {
        savedCallback.current();
      }
    }

    if (delay !== null) {
      const id = setInterval(tick, delay);
      return () => clearInterval(id);
    }
  }, [delay]);
}