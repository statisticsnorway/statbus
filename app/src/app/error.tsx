"use client";

import logger from "@/lib/logger";
import { useEffect } from "react";

export default function ErrorPage({
  error,
}: {
  readonly error: Error & { digest?: string };
}) {
  useEffect(() => {
    logger.error(`Caught by ErrorBoundary ${error.message}`);
  }, [error]);

  return (
    <main className="py-12 mx-auto text-center">
      <h1 className="text-xl mb-3">Oops</h1>
      <p>Something bad happened. Please try again a little later</p>
    </main>
  );
}
