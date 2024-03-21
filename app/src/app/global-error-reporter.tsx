"use client";
import { useEffect } from "react";
import logger from "@/lib/logger";

export default function GlobalErrorReporter() {
  useEffect(() => {
    window.onerror = function (message, source, lineno, colno, error) {
      logger.error(
        { error: { message: error?.message, stack: error?.stack } },
        `${message}`
      );

      return true;
    };

    window.onunhandledrejection = function (event) {
      logger.error(
        { ...event },
        `An unhandled promise rejection occurred: ${event.reason}`
      );

      event.preventDefault();
    };
  }, []);

  return null;
}
