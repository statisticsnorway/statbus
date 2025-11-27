"use client";

import React, { useState } from "react";
import { useAuth } from "@/atoms/auth";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";

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
    <form onSubmit={handleLogout} className="bg-gray-100 p-6">
      <div className="flex flex-col items-end space-y-4">
        {error && <p className="text-sm text-red-500 text-right">{error}</p>}
        <Button type="submit" disabled={isLoading}>
          <LogOut className="w-4 h-4" />
          {isLoading ? "Logging out..." : "Log out"}
        </Button>
      </div>
    </form>
  );
}
