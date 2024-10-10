"use client";
import { useContext } from "react";
import { SelectionContext } from "@/app/search/selection-context";

export const useSelectionContext = () => {
  const context = useContext(SelectionContext);
  if (!context) {
    throw new Error("useSelectionContext must be used within a SelectionProvider");
  }
  return context;
};
