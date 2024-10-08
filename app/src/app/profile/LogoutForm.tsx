"use client";

import React from "react";
import { useRouter } from "next/navigation";

export default function LogoutForm() {
  const router = useRouter();

  const handleLogout = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    await fetch("/api/auth/logout", { method: "POST" });
    router.push("/login");
  };

  return (
    <form
      onSubmit={handleLogout}
      className="flex justify-end bg-gray-100 p-6"
    >
      <button
        type="submit"
        className="me-2 rounded-md bg-gray-800 px-5 py-2.5 text-sm font-medium text-white hover:bg-gray-900 focus:outline-none focus:ring-2 focus:ring-indigo-600"
      >
        Log out
      </button>
    </form>
  );
}
