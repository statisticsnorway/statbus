"use client";
import { createContext, ReactNode, useEffect, useState } from "react";
import { Tables } from "@/lib/database.types";
import logger from "@/lib/client-logger";

interface TimeContextState {
  readonly periods: Tables<"relative_period_with_time">[];
  readonly selectedPeriod: Tables<"relative_period_with_time">;
}

const TimeContext = createContext<TimeContextState | null>(null);

export const TimeProvider = ({
  children,
}: {
  readonly children: ReactNode;
}) => {
  const [periods, setPeriods] = useState<Tables<"relative_period_with_time">[]>(
    []
  );

  useEffect(() => {
    (async () => {
      try {
        const response = await fetch("/api/relative-periods");

        if (
          response.ok &&
          response.headers.get("content-type") === "application/json"
        ) {
          const data = await response.json();
          setPeriods(data);
        }
      } catch (e) {
        logger.error(e, "failed to fetch relative periods");
      }
    })();
  }, []);

  return (
    <TimeContext.Provider
      value={{
        periods,
        selectedPeriod: periods[0],
      }}
    >
      {children}
    </TimeContext.Provider>
  );
};
