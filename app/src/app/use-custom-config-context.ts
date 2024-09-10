import { useContext } from "react";
import { CustomConfigContext } from "./custom-config-context";

export const useCustomConfigContext = () => {
  const context = useContext(CustomConfigContext);

  if (!context) {
    throw new Error(
      "useCustomConfigContext must be used within a CustomConfigProvider"
    );
  }
  return context;
};
