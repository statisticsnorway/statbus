"use client";
import { ReactNode, useMemo } from "react";
import useCustomConfig from "./use-custom-config";
import { CustomConfigContext } from "./custom-config-context";

interface CustomConfigProviderProps {
  readonly children: ReactNode;
}

export default function CustomConfigProvider(props: CustomConfigProviderProps) {
  const { statDefinitions, externalIdentTypes } = useCustomConfig();

  const value = useMemo(
    () => ({ statDefinitions, externalIdentTypes }),
    [statDefinitions, externalIdentTypes]
  );

  return (
    <CustomConfigContext.Provider value={value}>
      {props.children}
    </CustomConfigContext.Provider>
  );
}
