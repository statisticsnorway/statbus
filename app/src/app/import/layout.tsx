
"use client";

import { usePathname } from "next/navigation";

export default function ImportLayout({
  children,
  progress,
}: {
  readonly children: React.ReactNode;
  readonly progress: React.ReactNode;
}) {
  const pathname = usePathname();
  const isJobsPage = pathname.startsWith("/import/jobs");

  if (isJobsPage) {
    // As wide as the jobs table needs, never wider than the window: a wider table
    // (e.g. the data page) scrolls inside its own box, not the page.
    return (
      <main className="mx-auto w-fit min-w-0 max-w-[100vw] px-4 sm:px-6 lg:px-8 py-8 md:py-12">
        {children}
      </main>
    );
  }

  return (
    <main className="w-full mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 md:py-12 grid lg:grid-cols-12 gap-8">
      <aside className="p-6 pb-12 col-span-12 lg:col-span-4 bg-ssb-light">
        {progress}
      </aside>
      <div className="flex-1 col-span-12 lg:col-span-8 py-6">
        <div className="max-w-2xl mx-auto">{children}</div>
      </div>
    </main>
  );
}
