import React from "react";

export default function GettingStartedLayout({
  children,
  progress,
}: {
  readonly children: React.ReactNode;
  readonly progress: React.ReactNode;
}) {
  return (
    <main className="w-full mx-auto max-w-screen-xl px-2 py-8 md:py-24 grid lg:grid-cols-12 gap-8">
      <aside className="p-6 col-span-12 lg:col-span-4 bg-ssb-light">
        {progress}
      </aside>
      <div className="flex-1 col-span-12 lg:col-span-8">
        <div className="max-w-2xl mx-auto">{children}</div>
      </div>
    </main>
  );
}
