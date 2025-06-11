"use client";

import { ReactNode, useEffect } from "react";
import { setupGlobalErrorHandler } from "@/utils/auth/global-error-handler";

export default function RootLayoutClient({ children }: { readonly children: ReactNode }) {
  useEffect(() => {
    // Set up global error handler for auth errors
    setupGlobalErrorHandler();
    // This effect should only run once on mount
  }, []);

  // InitialStateHydrator wrapper removed.
  return <>{children}</>;
}
