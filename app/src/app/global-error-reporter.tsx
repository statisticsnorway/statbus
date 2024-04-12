"use client";
import { useEffect } from "react";
import logger from "@/lib/client-logger";

export default function GlobalErrorReporter() {
  const onError = function (e: ErrorEvent) {
    logger.error(e.error, `${e.message}`);
  };

  const onUnhandledRejection = function (e: PromiseRejectionEvent) {
    e.preventDefault();
    logger.error(
      { ...e },
      `An unhandled promise rejection occurred: ${e.reason}`
    );
  };

  useEffect(() => {
    window.addEventListener("error", onError);
    window.addEventListener("unhandledrejection", onUnhandledRejection);
    return () => {
      window.removeEventListener("error", onError);
      window.removeEventListener("unhandledrejection", onUnhandledRejection);
    };
  }, []);

  return null;
}
