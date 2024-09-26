import { useAuth } from "@/hooks/useAuth";
import logger from "@/lib/client-logger";
import { useState, useEffect } from "react";
import { TimeContext } from "./types";

export default function useTimeContexts() {
  const { isAuthenticated } = useAuth();
  const [timeContexts, setTimeContexts] = useState<TimeContext[]>([]);

  useEffect(() => {
    if (isAuthenticated) {
      (async () => {
        try {
          const response = await fetch("/api/time-contexts");

        if (
          response.ok &&
          response.headers.get("content-type") === "application/json"
        ) {
          const data = await response.json();
          setTimeContexts(data);
        }
        } catch (e) {
          logger.error(e, "failed to fetch time contexts");
        }
      })();
    }
  }, [isAuthenticated]);

  return timeContexts;
}
