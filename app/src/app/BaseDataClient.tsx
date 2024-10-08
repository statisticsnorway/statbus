"use client";

import React, { createContext, useContext, ReactNode } from 'react';
import { BaseData } from './BaseDataServer';

// Create a context for the base data
const BaseDataContext = createContext<BaseData>({} as BaseData);

// Hook to use the base data context
export const useBaseData = () => {
  const context = useContext(BaseDataContext);
  if (!context) {
    throw new Error("useBaseData must be used within a ClientBaseDataProvider");
  }
  return context;
};

// Client component to provide base data context
export const ClientBaseDataProvider = ({ children, baseData }: { children: ReactNode, baseData: BaseData }) => (
  <BaseDataContext.Provider value={baseData}>
    {children}
  </BaseDataContext.Provider>
);
