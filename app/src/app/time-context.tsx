"use client";
import { createContext, useContext, useState, useMemo, ReactNode, useEffect, useCallback } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import logger from "@/lib/client-logger";
import type { TimeContext as TimeContextType } from "@/app/types";

interface TimeContextState {
  readonly timeContexts: TimeContextType[];
  readonly selectedTimeContext: TimeContextType | null;
  readonly setSelectedTimeContext: (period: TimeContextType) => void;
  readonly appendTcParam: (url: string) => string;
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
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [timeContexts, setTimeContexts] = useState<TimeContextType[]>([]);

  const [selectedTimeContext, setSelectedTimeContext] = useState<TimeContextType | null>(null);

  const updateQueryParam = useCallback((tcIdent: string | null) => {
    const query = new URLSearchParams(searchParams.toString());
    if (tcIdent) {
      query.set(TC_QUERY_PARAM, tcIdent);
    }
    window.history.replaceState(null, "", `${pathname}?${query.toString()}`);
  }, [pathname, searchParams]);

  useEffect(() => {
    const handleRouteChange = () => {
      const query = new URLSearchParams(searchParams.toString());
      const tc = query.get(TC_QUERY_PARAM);
      if (!tc && selectedTimeContext) {
        updateQueryParam(selectedTimeContext.ident);
      } else if (!tc && timeContexts.length > 0) {
        const firstTimeContext = timeContexts[0];
        if (firstTimeContext?.ident) {
          setSelectedTimeContext(firstTimeContext);
          updateQueryParam(firstTimeContext.ident);
        }
      } else {
        const selectedContext = timeContexts.find(
          (context) => context.ident === tc
        );
        if (selectedContext) {
          setSelectedTimeContext(selectedContext);
        }
      }
    };

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
        handleRouteChange();
      }

      handleRouteChange();
    }
  }, [isAuthenticated, timeContexts, pathname, searchParams, updateQueryParam, selectedTimeContext]);

  useEffect(() => {
    if (selectedTimeContext && selectedTimeContext.ident != null) {
      updateQueryParam(selectedTimeContext.ident);
    }
  }, [selectedTimeContext, pathname, searchParams, updateQueryParam]);

  const appendTcParam = useCallback((url: string) => {
    const urlObj = new URL(url, window.location.origin);
    const tc = selectedTimeContext?.ident;

    if (tc && !urlObj.searchParams.has(TC_QUERY_PARAM)) {
      urlObj.searchParams.set(TC_QUERY_PARAM, tc);
    }

    return urlObj.toString().replace(window.location.origin, '');
  }, [selectedTimeContext]);

  const value = useMemo(
    () => ({
      timeContexts,
      selectedTimeContext,
      setSelectedTimeContext,
      appendTcParam,
    }),
    [timeContexts, selectedTimeContext, appendTcParam]
  );

  return (
    <TimeContext.Provider value={value}>
      {children}
    </TimeContext.Provider>
  );
}
