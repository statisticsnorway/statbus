"use client";
import { createContext, useContext, useState, useMemo, ReactNode, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import logger from "@/lib/client-logger";
import type { TimeContext as TimeContextType } from "@/app/types";

interface TimeContextState {
  readonly timeContexts: TimeContextType[];
  readonly selectedTimeContext: TimeContextType | null;
  readonly setSelectedTimeContext: (period: TimeContextType) => void;
}

const TC_QUERY_PARAM = "tc";
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
  const router = useRouter();
  const [timeContexts, setTimeContexts] = useState<TimeContextType[]>([]);

  const [selectedTimeContext, setSelectedTimeContext] = useState<TimeContextType | null>(null);

  useEffect(() => {
    if (typeof window !== "undefined" && isAuthenticated) {
      const fetchTimeContexts = async () => {
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
      };

      if (timeContexts.length === 0) {
        fetchTimeContexts();
      } else {
        const query = new URLSearchParams(window.location.search);
        const tc = query.get(TC_QUERY_PARAM);

        if (!tc) {
          const firstTimeContext = timeContexts[0];
          if (firstTimeContext?.ident) {
            setSelectedTimeContext(firstTimeContext);
            query.set(TC_QUERY_PARAM, firstTimeContext.ident);
            router.replace(`?${query.toString()}`);
          }
        } else {
          const selectedContext = timeContexts.find(
            (context) => context.ident === tc
          );
          if (selectedContext) {
            setSelectedTimeContext(selectedContext);
          }
        }
      }
    }
  }, [isAuthenticated, timeContexts, router]);

  useEffect(() => {
    if (selectedTimeContext) {
      const query = new URLSearchParams(window.location.search);
      query.set(TC_QUERY_PARAM, selectedTimeContext.ident);
      router.replace(`?${query.toString()}`);
    }
  }, [selectedTimeContext, router]);

  const value = useMemo(
    () => ({ timeContexts, selectedTimeContext, setSelectedTimeContext }),
    [timeContexts, selectedTimeContext]
  );

  const appendTcParam = (url: string) => {
    const query = new URLSearchParams(window.location.search);
    const tc = query.get(TC_QUERY_PARAM);
    return tc ? `${url}?${TC_QUERY_PARAM}=${tc}` : url;
  };
  return (
    <TimeContext.Provider value={{ ...value, appendTcParam }}>
      {children}
    </TimeContext.Provider>
  );
}
