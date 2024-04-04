import logger from "@/lib/client-logger";
import { useEffect, useState } from "react";
import { Period } from "@/app/types";

export default function useRelativePeriods() {
  const [periods, setPeriods] = useState<Period[]>([]);

  useEffect(() => {
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
  }, []);

  return periods;
}
