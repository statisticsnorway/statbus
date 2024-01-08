import React from "react";

export default function GettingStartedLayout({children}: { children: React.ReactNode }) {
  return (
    <main className="w-2/3 max-w-2xl mx-auto p-24 text-md">
      {children}
    </main>
  )
}
