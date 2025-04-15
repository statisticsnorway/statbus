"use client";

import { useEffect } from "react";
import { useAuth } from "@/hooks/useAuth";
import { useRouter } from "next/navigation";

export default function ClientRedirect() {
  const { isAuthenticated, isLoading } = useAuth();
  const router = useRouter();

  // Redirect if already authenticated
  useEffect(() => {
    // Only redirect if authentication check is complete and user is authenticated
    if (!isLoading && isAuthenticated) {
      // Use window.location for a hard redirect to avoid Next.js router issues
      window.location.href = "/";
    }
  }, [isAuthenticated, isLoading]);

  return null;
}
