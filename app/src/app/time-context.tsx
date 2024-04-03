"use client";
import { createContext } from "react";
import type { Period } from "@/app/types";

interface TimeContextState {
  readonly periods: Period[];
  readonly selectedPeriod: Period | null;
  readonly setSelectedPeriod: (period: Period) => void;
}

export const TimeContext = createContext<TimeContextState | null>(null);
