"use client";
import { createContext } from "react";
import type { TimeContext } from "@/app/types";

interface TimeContextState {
  readonly timeContexts: TimeContext[];
  readonly selectedTimeContext: TimeContext | null;
  readonly setSelectedTimeContext: (period: TimeContext) => void;
}

export const TimeContextState = createContext<TimeContextState | null>(null);
