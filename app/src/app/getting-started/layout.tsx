import React from "react";

export default function GettingStartedLayout({
  children,
}: {
  readonly children: React.ReactNode;
}) {
  return (
    <main className="text-md mx-auto max-w-2xl px-2 py-8 md:py-24 lg:w-2/3">
      {children}
    </main>
  );
}
