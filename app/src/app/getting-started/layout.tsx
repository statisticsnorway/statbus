import React from "react";

export default function GettingStartedLayout({
  children,
  progress,
}: {
  readonly children: React.ReactNode;
  readonly progress: React.ReactNode;
}) {
  return (
    <main className="w-full mx-auto max-w-screen-2xl px-2 py-8 md:py-24 grid xl:grid-cols-12 gap-8">
      <aside className="p-6 col-span-12 xl:col-span-4 xl:bg-gray-50">
        {progress}
      </aside>
      <div className="flex-1 col-span-12 xl:col-span-8">
        <div className="max-w-2xl mx-auto">{children}</div>
      </div>
    </main>
  );
}
