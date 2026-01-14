"use client";

import { Suspense } from "react";
import { useAtomValue } from "jotai";
import { timeContextAutoSelectEffectAtom } from "@/atoms/app-derived";
import Dashboard from "@/app/dashboard/page";

export default function HomePage() {
  // BATTLE WISDOM: This page must render immediately during client-side navigation
  // from /login to /. Blocking on data loading here causes router.push("/") to hang
  // because Next.js waits for the page to render before completing navigation.
  
  // Activate the time context auto-select effect by reading it.
  // This ensures a valid time context is selected when the page loads.
  useAtomValue(timeContextAutoSelectEffectAtom);
  
  // The Dashboard component and its children use Suspense boundaries for data loading,
  // so we can render immediately and let those boundaries handle loading states.
  return (
    <Suspense fallback={
      <main className="flex-grow p-4 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-gray-900 mx-auto mb-4"></div>
          <p>Loading dashboard...</p>
        </div>
      </main>
    }>
      <Dashboard />
    </Suspense>
  );
}
