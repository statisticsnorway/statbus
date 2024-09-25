import { useEffect, useState } from "react";
import { ExternalIdentType, StatDefinition } from "./types";
import logger from "@/lib/client-logger";

export default function useCustomConfig() {
  const [statDefinitions, setStatDefinitions] = useState<StatDefinition[]>([]);
  const [externalIdentTypes, setExternalIdentTypes] = useState<ExternalIdentType[]>([]);

  useEffect(() => {
    (async () => {
      try {
        const response = await fetch("/api/custom-config");

        if (
          response.ok &&
          response.headers.get("content-type") === "application/json"
        ) {
          const data = await response.json();

          setStatDefinitions(data.statDefinitions);
          setExternalIdentTypes(data.externalIdentTypes);
        } else {
          // Capture the error stack trace
          const error = new Error("Invalid response format or content type");
          logger.error(error, "failed to fetch stat definitions and external ident types");
        }
      } catch (e) {
        logger.error(e,"failed to fetch stat definitions and external ident types");
      }
    })();
  }, []);

  return { statDefinitions, externalIdentTypes };
}
