"use client";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
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

  useGuardedEffect(() => {
    window.addEventListener("error", onError);
    window.addEventListener("unhandledrejection", onUnhandledRejection);
    return () => {
      window.removeEventListener("error", onError);
      window.removeEventListener("unhandledrejection", onUnhandledRejection);
    };
  }, [], 'GlobalErrorReporter:setupListeners');

  return null;
}
