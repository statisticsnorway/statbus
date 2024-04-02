"use client";
import {
  createContext,
  ReactNode,
  useContext,
  useEffect,
  useState,
} from "react";
import { Tables } from "@/lib/database.types";
import logger from "@/lib/client-logger";

interface TimeContextState {
  readonly periods: Tables<"relative_period_with_time">[];
  readonly selectedPeriod: Tables<"relative_period_with_time"> | null;
  readonly setSelectedPeriod: (
    period: Tables<"relative_period_with_time">
  ) => void;
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

  const [selectedPeriod, setSelectedPeriod] =
    useState<Tables<"relative_period_with_time"> | null>(null);

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
          setSelectedPeriod(data[0]);
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
        selectedPeriod,
        setSelectedPeriod,
      }}
    >
      {children}
    </TimeContext.Provider>
  );
};

export const useTimeContext = () => {
  const context = useContext(TimeContext);

  if (!context) {
    throw new Error("useTimeContext must be used within a TimeProvider");
  }

  return context;
};
