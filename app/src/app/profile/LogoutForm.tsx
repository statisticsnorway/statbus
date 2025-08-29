"use client";

import React, { useState } from "react";
import { useAuth } from "@/atoms/auth";

export default function LogoutForm() {
  const { logout } = useAuth();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogout = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setError(null);
    setIsLoading(true);
    try {
      await logout();
      // On success, the RedirectHandler will navigate away.
    } catch (err: any) {
      setError(err.message || "An unexpected error occurred during logout.");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <form
      onSubmit={handleLogout}
      className="bg-gray-100 p-6"
    >
      <div className="flex flex-col items-end space-y-4">
        {error && (
          <p className="text-sm text-red-500 text-right">{error}</p>
        )}
        <button
          type="submit"
          disabled={isLoading}
          className="me-2 rounded-md bg-gray-800 px-5 py-2.5 text-sm font-medium text-white hover:bg-gray-900 focus:outline-hidden focus:ring-2 focus:ring-indigo-600 disabled:opacity-50"
        >
          {isLoading ? "Logging out..." : "Log out"}
        </button>
      </div>
    </form>
  );
}
