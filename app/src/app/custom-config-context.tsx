"use client";
import { createContext } from "react";
import { ExternalIdentType, StatDefinition } from "./types";
interface CustomConfigContextData {
  readonly statDefinitions: StatDefinition[];
  readonly externalIdentTypes: ExternalIdentType[];
}
export const CustomConfigContext =
  createContext<CustomConfigContextData | null>(null);
