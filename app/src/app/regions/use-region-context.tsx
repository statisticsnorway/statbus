"use client";

import { useContext } from "react";
import { RegionContext } from "./region-context";

export const useRegionContext = () => {
  const context = useContext(RegionContext);
  if (!context) {
    throw new Error("useRegionContext must be used within a RegionProvider");
  }
  return context;
};
