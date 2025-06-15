"use client";

import React, { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAtomValue } from "jotai";
import { authStatusAtom } from "@/atoms";
import LoginForm from "./LoginForm"; // LoginForm.tsx is in the same directory

export default function LoginClientBoundary() {
  const router = useRouter();
  const authStatus = useAtomValue(authStatusAtom);

  useEffect(() => {
    // Only redirect if auth status is definitively resolved (not loading) and user is authenticated.
    if (!authStatus.loading && authStatus.isAuthenticated) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("LoginClientBoundary: User is authenticated, redirecting to /");
      }
      router.push('/'); // Redirect to home, middleware should handle further redirection if needed.
    }
  }, [authStatus.isAuthenticated, authStatus.loading, router]);

  // Render the LoginForm. The useEffect above will handle redirection if/when auth state changes.
  return <LoginForm />;
}
