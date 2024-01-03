import React from "react";

export default function GettingStartedLayout({children}: { children: React.ReactNode }) {
  return (
    <div className="w-2/3 max-w-2xl mx-auto p-24">
      <main className="text-md">
        {children}
      </main>
    </div>
  )
}
