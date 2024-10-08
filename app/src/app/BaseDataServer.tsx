"use server";

import { getBaseData, BaseData } from "@/utils/base-data";
import { ClientBaseDataProvider } from "./BaseDataClient";

// Server component to fetch and provide base data
export const ServerBaseDataProvider = async ({ children }: { children: React.ReactNode }) => {
  const baseData = await getBaseData();

  return (
    <ClientBaseDataProvider baseData={baseData}>
      {children}
    </ClientBaseDataProvider>
  );
};
