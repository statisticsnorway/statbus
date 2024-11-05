"use client";
import { createContext } from "react";
import { StatisticalUnit } from "@/app/types";


export interface SelectionContextData {
  readonly selected: StatisticalUnit[];
  readonly clearSelected: () => void;
  readonly toggle: (unit: StatisticalUnit) => void;
}

export const SelectionContext = createContext<SelectionContextData | null>(null);
