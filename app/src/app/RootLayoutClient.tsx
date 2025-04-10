"use client";

import { ReactNode, useEffect } from "react";
import { setupGlobalErrorHandler } from "@/utils/auth/global-error-handler";

export default function RootLayoutClient({ children }: { readonly children: ReactNode }) {
  useEffect(() => {
    setupGlobalErrorHandler();
    // This effect should only run once on mount
  }, []);
  
  return <>{children}</>;
}
