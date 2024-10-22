"use server";

import React, { createContext, ReactNode, useContext } from 'react';
import { BaseData } from './BaseDataServer';

// Create a context for the server base data
const BaseDataServerContext = createContext<BaseData | undefined>(undefined);

// Hook to use the server base data context
export const useBaseDataServer = () => {
  const context = useContext(BaseDataServerContext);
  if (!context) {
    throw new Error("useBaseDataServer must be used within a BaseDataServerProvider");
  }
  return context;
};

// Server component to provide base data context
export const BaseDataServerProvider = ({ children, baseData }: { children: ReactNode, baseData: BaseData }) => {
  return (
    <BaseDataServerContext.Provider value={baseData}>
      {children}
    </BaseDataServerContext.Provider>
  );
};
