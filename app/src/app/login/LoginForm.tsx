"use client";

import React, { useState, useRef } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useAuth } from "@/atoms/auth";
import { useRouter } from "next/navigation";

interface LoginFormProps {
  nextPath: string | null;
}

export default function LoginForm({ nextPath }: LoginFormProps) {
  const { login, loginError } = useAuth();
  const [isLoading, setIsLoading] = useState(false);
  const emailInputRef = useRef<HTMLInputElement>(null);
  const [displayError, setDisplayError] = useState<string | null>(null);

  useGuardedEffect(() => {
    emailInputRef.current?.focus();
  }, [], 'LoginForm:focusEmailInput');

  // Map error codes to user-friendly messages
  const loginErrorMessages: Record<string, string> = {
    USER_NOT_FOUND: "User with this email not found.",
    USER_NOT_CONFIRMED_EMAIL: "Email not confirmed. Please check your inbox for a confirmation link.",
    USER_DELETED: "This user account has been marked as deleted.",
    USER_MISSING_PASSWORD: "Password cannot be empty. Please enter your password.",
    WRONG_PASSWORD: "Incorrect password. Please try again.",
    // Generic fallback for unmapped errors or if error_code is null but login failed
    DEFAULT: "Login failed. Please check your credentials and try again."
  };

  // Effect to translate the error from the atom into a displayable message.
  useGuardedEffect(() => {
    if (loginError) {
      const errorCode = loginError.code;
      const message = errorCode && loginErrorMessages[errorCode] 
                      ? loginErrorMessages[errorCode]
                      : (loginError.message || loginErrorMessages.DEFAULT);
      setDisplayError(message);
      setIsLoading(false); // Ensure loading is stopped on error.
    } else {
      setDisplayError(null);
    }
  }, [loginError], 'LoginForm:displayLoginError');

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setIsLoading(true);
    setDisplayError(null); // Clear previous errors on new submission
    
    const formData = new FormData(event.currentTarget);
    const email = formData.get("email") as string;
    const password = formData.get("password") as string;

    // The login action is now "fire and forget". It updates global state (authStatus or loginError).
    // This component re-renders based on those state changes.
    // We no longer need a try/catch block here.
    await login({ credentials: { email, password } });
    
    // The `isLoading` state is manually managed. It will be set to false either
    // by the error-handling useEffect above, or by the unmounting of this
    // component upon successful login and redirect.
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
        {displayError && (
          <div className="my-2 text-center text-sm text-red-500">
            {displayError}
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
