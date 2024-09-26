"use client";
import { ReactNode, useMemo, useState } from "react";
import { TimeContextState } from "@/app/time-context";
import type { TimeContext } from "@/app/types";
import useTimeContexts from "@/app/use-time-contexts";

interface TimeContextProviderProps {
  readonly children: ReactNode;
}

export default function TimeContextProvider(props: TimeContextProviderProps) {
  const timeContexts = useTimeContexts();
  const [selectedTimeContext, setSelectedTimeContext] = useState<TimeContext | null>(null);

  const value = useMemo(
    () => ({ timeContexts, selectedTimeContext, setSelectedTimeContext }),
    [timeContexts, selectedTimeContext, setSelectedTimeContext]
  );

  return (
    <TimeContextState.Provider value={value}>{props.children}</TimeContextState.Provider>
  );
}
