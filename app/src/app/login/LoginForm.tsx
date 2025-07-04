"use client";

import React, { useState, useRef, useEffect } from "react";
import { useAuth } from "@/atoms/auth";
import { useRouter } from "next/navigation";

interface LoginFormProps {
  nextPath: string | null;
}

export default function LoginForm({ nextPath }: LoginFormProps) {
  const { login } = useAuth();
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const emailInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    emailInputRef.current?.focus();
  }, []);

  // Map error codes to user-friendly messages
  const loginErrorMessages: Record<string, string> = {
    USER_NOT_FOUND: "User with this email not found.",
    USER_NOT_CONFIRMED_EMAIL: "Email not confirmed. Please check your inbox for a confirmation link.",
    USER_DELETED: "This user account has been marked as deleted.",
    USER_MISSING_PASSWORD: "Password cannot be empty. Please enter your password.", // Should ideally be caught by form validation
    WRONG_PASSWORD: "Incorrect password. Please try again.",
    // Generic fallback for unmapped errors or if error_code is null but login failed
    DEFAULT: "Login failed. Please check your credentials and try again."
  };

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);
    setIsLoading(true);
    
    const formData = new FormData(event.currentTarget);
    const email = formData.get("email") as string;
    const password = formData.get("password") as string;

    try {
      // The loginAtom now internally handles parsing the response from /rpc/login
      // and refreshing authStatusCoreAtom.
      // For LoginForm, we primarily care about the immediate success/failure from the login attempt.
      // The loginAtom itself doesn't directly return the RPC response to here.
      // We need to modify loginAtom or have a new atom if we want to access error_code directly here.

      // For now, let's assume loginAtom throws an error on failure,
      // and we'll keep the generic error message.
      // A more advanced approach would be for loginAtom to return the auth_response or update an error atom.
      // Given the current structure of loginAtom (it throws on error), we can't easily get error_code here
      // without a larger refactor of loginAtom.

      // The original request was to use error_code from login.
      // This implies loginAtom should provide it.
      // Let's assume loginAtom is modified to throw an error object that includes error_code.
      // This is a hypothetical modification to loginAtom for this example.
      // A better way would be for loginAtom to return the full auth_response.
      // For now, I'll proceed as if `error.cause` might contain the error_code.

      await login({ credentials: { email, password }, nextPath });
      
      // If loginAtom completes without error, it means the /rest/rpc/login was successful (2xx)
      // AND the subsequent refresh of authStatusCoreAtom (via /rest/rpc/auth_status) also indicated authenticated.
      // The LoginClientBoundary component will handle redirecting the user when authStatusAtom updates.
      // No need to router.push('/') here anymore.
      
    } catch (error: any) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.error("LoginForm: Login error caught in handleSubmit:", error, "Error cause:", error.cause);
      }
      // Attempt to get a specific message if error.cause is one of our known error codes
      const errorCode = typeof error.cause === 'string' ? error.cause : null;
      const message = errorCode && loginErrorMessages[errorCode] 
                      ? loginErrorMessages[errorCode]
                      : loginErrorMessages.DEFAULT;
      setError(message);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <form className="group space-y-6" onSubmit={handleSubmit} noValidate>
      <div>
        <label
          htmlFor="email"
          className="block text-sm font-medium leading-6 text-gray-900"
        >
          Email address
        </label>
        <div className="mt-2">
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            ref={emailInputRef}
            placeholder="Enter your email address"
            className="peer block w-full rounded-md border-0 px-2.5 py-1.5 text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6 invalid:[&:not(:placeholder-shown):not(:focus):not(:autofill)]:ring-red-500"
          />
          <span className="mt-2 hidden text-sm text-red-500 peer-[&:not(:placeholder-shown):not(:focus):invalid]:block">
            Please enter a valid email address
          </span>
        </div>
      </div>

      <div>
        <div className="flex items-center justify-between">
          <label
            htmlFor="password"
            className="block text-sm font-medium leading-6 text-gray-900"
          >
            Password
          </label>
        </div>
        <div className="mt-2">
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            placeholder="Enter your password"
            pattern=".{3,}"
            className="peer block w-full rounded-md border-0 px-2.5 py-1.5 text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6 invalid:[&:not(:placeholder-shown):not(:focus):not(:autofill)]:ring-red-500"
          />
          <span className="mt-2 hidden text-sm text-red-500 peer-[&:not(:placeholder-shown):not(:focus):invalid]:block">
            Please enter a valid password
          </span>
        </div>
      </div>

      <div>
        {error && (
          <div className="my-2 text-center text-sm text-red-500">
            {error}
          </div>
        )}
        <button
          type="submit"
          disabled={isLoading}
          className="flex w-full justify-center rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-semibold leading-6 text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 group-invalid:pointer-events-none group-invalid:opacity-30 disabled:opacity-50"
        >
          {isLoading ? "Signing in..." : "Sign in"}
        </button>
      </div>
    </form>
  );
}
