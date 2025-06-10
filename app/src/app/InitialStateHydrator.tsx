"use client";

import { useEffect, ReactNode } from "react";
import { useSetAtom } from "jotai";
import {
  authStatusAtom,
  baseDataAtom,
  type AuthStatus,
  type BaseData,
  type User,
} from "@/atoms"; // Assuming types and atoms are exported from @/atoms/index.ts

interface InitialStateHydratorProps {
  // This combined prop should match the return type of getBaseData in BaseDataServer.tsx
  initialData: BaseData & { isAuthenticated: boolean; user: User | null };
  children: ReactNode;
}

export function InitialStateHydrator({
  initialData,
  children,
}: InitialStateHydratorProps) {
  const setAuthStatus = useSetAtom(authStatusAtom);
  const setBaseData = useSetAtom(baseDataAtom);

  useEffect(() => {
    // Hydrate Auth Status
    const newAuthStatus: AuthStatus = {
      isAuthenticated: initialData.isAuthenticated,
      user: initialData.user,
      tokenExpiring: false, // Assuming token is fresh if just authenticated server-side or not applicable
    };
    setAuthStatus(newAuthStatus);

    // Hydrate Base Data
    // The initialData object already contains all fields of BaseData
    // plus isAuthenticated and user. We can spread it.
    const newBaseData: BaseData = {
      statDefinitions: initialData.statDefinitions,
      externalIdentTypes: initialData.externalIdentTypes,
      statbusUsers: initialData.statbusUsers,
      timeContexts: initialData.timeContexts,
      defaultTimeContext: initialData.defaultTimeContext,
      hasStatisticalUnits: initialData.hasStatisticalUnits,
    };
    setBaseData(newBaseData);

    // This effect should only run once on mount to hydrate the initial state
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Pass empty array for initialData if it's stable, or include if it can change

  return <>{children}</>;
}