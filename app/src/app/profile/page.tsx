"use client"; // Make this a client component to use hooks

import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import LogoutForm from "./LogoutForm";
import { logger } from "@/lib/client-logger";
import { useAuth } from "@/atoms/auth"; // Use Jotai hook for auth state

export default function ProfilePage() {
  const [isMounted, setIsMounted] = useState(false);
  const { isAuthenticated, user, loading: authLoading } = useAuth();

  useGuardedEffect(() => {
    setIsMounted(true);
  }, [], 'ProfilePage:setMounted');

  // The redirect for unauthenticated users and associated logging is now handled
  // declaratively by the centralized NavigationManager. This component no longer
  // needs to implement its own redirect logic.

  // Show loading state or if user is null (which shouldn't happen if authenticated)
  if (!isMounted || authLoading) {
    return (
      <main className="flex flex-col items-center justify-center px-2 py-8 md:py-24 min-h-screen">
        <div>Loading profile...</div>
      </main>
    );
  }

  if (!isAuthenticated || !user) {
    // This case should ideally be handled by the redirect in useEffect,
    // but as a fallback or if redirect hasn't happened yet:
    return (
      <main className="flex flex-col items-center justify-center px-2 py-8 md:py-24 min-h-screen">
        <div>Redirecting to login...</div>
      </main>
    );
  }
    
  return (
    <main className="flex flex-col items-center justify-between px-2 py-8 md:py-24">
      <div className="mx-auto sm:w-full lg:max-w-5xl">
        <div>
          <h3 className="text-base font-semibold leading-7 text-gray-900">
            Profile Information
          </h3>
          <p className="mt-1 max-w-2xl text-sm leading-6 text-gray-500">
            This is what the system knows about you
          </p>
        </div>
        <div className="mt-6 border-t border-gray-100">
          <dl className="divide-y divide-gray-100">
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                User ID
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.uid}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Full name
              </dt>
              <dd className="mt-1 text-sm capitalize leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.email?.split("@")[0].replace(/\./, " ")}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Email address
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.email}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Role
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.statbus_role}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Last sign in
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.last_sign_in_at ? new Date(user.last_sign_in_at).toLocaleString() : "N/A"}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Account created
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.created_at ? new Date(user.created_at).toLocaleString() : "N/A"}
              </dd>
            </div>
          </dl>
        </div>
        <LogoutForm />
      </div>
    </main>
  );
}
