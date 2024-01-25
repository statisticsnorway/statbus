import React from "react";

export default function GettingStartedLayout({children}: { readonly children: React.ReactNode }) {
  return (
    <main className="mx-auto text-md max-w-2xl py-8 px-2 md:py-24 lg:w-2/3">
      {children}
    </main>
  )
}
