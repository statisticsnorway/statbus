"use client";
import { Tables } from "@/lib/database.types";
import { createContext } from "react";

export interface CartContextData {
  readonly selected: Tables<"statistical_unit">[];
  readonly clearSelected: () => void;
  readonly toggle: (unit: Tables<"statistical_unit">) => void;
}

export const CartContext = createContext<CartContextData | null>(null);
