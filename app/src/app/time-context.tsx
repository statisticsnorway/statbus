"use client";
import { createContext, useContext, useState, useMemo, ReactNode, useEffect, useCallback, Suspense } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import type { TimeContextRow } from "@/app/types";
import { useBaseData } from "@/app/BaseDataClient";
import { useAuth } from "@/hooks/useAuth";


interface TimeContextState {
  readonly selectedTimeContext: TimeContextRow | null;
  readonly setSelectedTimeContext: (period: TimeContextRow) => void;
  readonly setSelectedTimeContextFromIdent: (ident: string) => void;
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
  const { timeContexts, defaultTimeContext, hasStatisticalUnits } = useBaseData();
  const { isAuthenticated } = useAuth();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const [selectedTimeContext, setSelectedTimeContext] = useState<TimeContextRow | null>();

  const setSelectedTimeContextFromIdent = useCallback((ident: string) => {
    const selectedContext = timeContexts.find(
      (timeContext) => timeContext.ident === ident
    );
    if (selectedContext) {
      setSelectedTimeContext(selectedContext);
    } else {
      console.warn(`Time context with ident ${ident} not found.`);
    }
  }, [timeContexts]);

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
      const tcQueryParam = query.get(TC_QUERY_PARAM);

      if (selectedTimeContext) {
        updateQueryParam(selectedTimeContext.ident);
      } else if (tcQueryParam) {
        setSelectedTimeContextFromIdent(tcQueryParam);
      } else {
        if (defaultTimeContext?.ident) {
          setSelectedTimeContext(defaultTimeContext);
          updateQueryParam(defaultTimeContext.ident);
        }
      }
    };

    if (isAuthenticated && hasStatisticalUnits) {
      handleRouteChange();
    }

  }, [pathname, searchParams, updateQueryParam, selectedTimeContext, timeContexts, defaultTimeContext, hasStatisticalUnits, isAuthenticated]);

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
      setSelectedTimeContextFromIdent,
      appendTcParam,
    } as TimeContextState),
    [timeContexts, selectedTimeContext, setSelectedTimeContextFromIdent, appendTcParam]
  );

  return (
    <Suspense fallback={<div>Loading...</div>}>
      <TimeContext.Provider value={value}>
        {children}
      </TimeContext.Provider>
    </Suspense>
  );
}
