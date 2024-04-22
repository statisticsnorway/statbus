"use client";
import { Dispatch, createContext } from "react";

export interface RegionContextState {
  readonly regions: RegionState;
  readonly dispatch: Dispatch<RegionAction>;
  readonly regionsResult?: RegionResult;
  readonly searchParams: URLSearchParams;
  readonly isLoading: boolean;
}

export const RegionContext = createContext<RegionContextState | null>(null);
