"use client";
import { ReactNode, useEffect, useState } from "react";
import logger from "@/lib/client-logger";
import { TimeContext } from "@/app/time-context";
import type { Period } from "@/app/types";

interface TimeContextProviderProps {
  readonly children: ReactNode;
}

export default function TimeContextProvider(props: TimeContextProviderProps) {
  const [periods, setPeriods] = useState<Period[]>([]);
  const [selectedPeriod, setSelectedPeriod] = useState<Period | null>(null);

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
      {props.children}
    </TimeContext.Provider>
  );
}
