import React from "react";

export default function GettingStartedLayout({
  children,
  progress,
}: {
  readonly children: React.ReactNode;
  readonly progress: React.ReactNode;
}) {
  return (
    <main className="w-full max-w-screen-2xl mx-auto flex justify-center gap-12 px-2 py-8 md:py-24">
      <aside className="bg-gray-50 p-6">{progress}</aside>
      <div className="max-w-2xl">{children}</div>
    </main>
  );
}
