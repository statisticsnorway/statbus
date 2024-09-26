import { useAuth } from "@/hooks/useAuth";
import { useState, useEffect } from "react";

export default function useRelativePeriods() {
  const { isAuthenticated } = useAuth();
  const [periods, setPeriods] = useState<Period[]>([]);

  useEffect(() => {
    if (isAuthenticated) {
      (async () => {
        try {
          const response = await fetch("/api/relative-periods");

        if (
          response.ok &&
          response.headers.get("content-type") === "application/json"
        ) {
          const data = await response.json();
          setPeriods(data);
        }
        } catch (e) {
          logger.error(e, "failed to fetch relative periods");
        }
      })();
    }
  }, [isAuthenticated]);

  return periods;
}
