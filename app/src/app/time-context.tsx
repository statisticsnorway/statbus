import { createContext, ReactNode } from "react";
import { Tables } from "@/lib/database.types";

interface TimeContextState {
  readonly periods: Tables<"relative_period_with_time">[];
  readonly selectedPeriod: Tables<"relative_period_with_time">;
}

const TimeContext = createContext<TimeContextState | null>(null);

export const TimeProvider = ({
  children,
  periods,
}: {
  readonly children: ReactNode;
  readonly periods: Tables<"relative_period_with_time">[];
}) => {
  const ctx: TimeContextState = {
    periods,
    selectedPeriod: periods[0],
  };

  return <TimeContext.Provider value={ctx}>{children}</TimeContext.Provider>;
};
