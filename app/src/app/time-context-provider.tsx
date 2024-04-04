"use client";
import { ReactNode, useMemo, useState } from "react";
import { TimeContext } from "@/app/time-context";
import type { Period } from "@/app/types";
import useRelativePeriods from "@/app/use-relative-periods";

interface TimeContextProviderProps {
  readonly children: ReactNode;
}

export default function TimeContextProvider(props: TimeContextProviderProps) {
  const periods = useRelativePeriods();
  const [selectedPeriod, setSelectedPeriod] = useState<Period | null>(null);

  const value = useMemo(
    () => ({ periods, selectedPeriod, setSelectedPeriod }),
    [periods, selectedPeriod, setSelectedPeriod]
  );

  return (
    <TimeContext.Provider value={value}>{props.children}</TimeContext.Provider>
  );
}
