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
    // If authStatus.isAuthenticated is true, authStatus.loading is implicitly false
    // based on the definition of authStatusAtom.
    if (authStatus.isAuthenticated) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("LoginClientBoundary: User is authenticated, redirecting to /");
      }
      router.push('/'); // Redirect to home, middleware should handle further redirection if needed.
    }
  }, [authStatus.isAuthenticated, router]);

  // Render the LoginForm. The useEffect above will handle redirection if/when auth state changes.
  return <LoginForm />;
}
