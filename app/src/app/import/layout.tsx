
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
  const isJobsPage = pathname === "/import/jobs";

  if (isJobsPage) {
    return (
      <main className="w-full mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 md:py-12">
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
