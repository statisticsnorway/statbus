"use client";

import logger from "@/lib/client-logger";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export default function ErrorPage({
  error,
}: {
  readonly error: Error & { digest?: string };
}) {
  useGuardedEffect(() => {
    logger.error(error, error.message);
  }, [error], 'ErrorPage:logError');

  return (
    <main className="py-12 mx-auto text-center">
      <h1 className="text-xl mb-3">Oops</h1>
      <p>Something bad happened. Please try again a little later</p>
    </main>
  );
}
