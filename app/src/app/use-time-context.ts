import { useContext } from "react";
import { TimeContextState } from "@/app/time-context";

export const useTimeContext = () => {
  const context = useContext(TimeContextState);

  if (!context) {
    throw new Error("useTimeContext must be used within a TimeProvider");
  }

  return context;
};
