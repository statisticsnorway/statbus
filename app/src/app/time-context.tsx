"use client";
import { createContext, useContext, useState, useMemo, ReactNode, useEffect } from "react";
import { useAuth } from "@/hooks/useAuth";
import logger from "@/lib/client-logger";
import type { TimeContext as TimeContextType } from "@/app/types";

interface TimeContextState {
  readonly timeContexts: TimeContextType[];
  readonly selectedTimeContext: TimeContextType | null;
  readonly setSelectedTimeContext: (period: TimeContextType) => void;
}

const TimeContext = createContext<TimeContextState | null>(null);

export const useTimeContext = () => {
  const context = useContext(TimeContext);

  if (!context) {
    throw new Error("useTimeContext must be used within a TimeContextProvider");
  }

  return context;
};

interface TimeContextProviderProps {
  readonly children: ReactNode;
}

export function TimeContextProvider({ children }: TimeContextProviderProps) {
  const { isAuthenticated } = useAuth();
  const [timeContexts, setTimeContexts] = useState<TimeContextType[]>([]);
  const [selectedTimeContext, setSelectedTimeContext] = useState<TimeContextType | null>(null);

  useEffect(() => {
    if (isAuthenticated) {
      (async () => {
        try {
          const response = await fetch("/api/time-contexts");

          if (
            response.ok &&
            response.headers.get("content-type") === "application/json"
          ) {
            const data = await response.json();
            setTimeContexts(data);
          }
        } catch (e) {
          logger.error(e, "failed to fetch time contexts");
        }
      })();
    }
  }, [isAuthenticated]);

  const value = useMemo(
    () => ({ timeContexts, selectedTimeContext, setSelectedTimeContext }),
    [timeContexts, selectedTimeContext]
  );

  return (
    <TimeContext.Provider value={value}>{children}</TimeContext.Provider>
  );
}
