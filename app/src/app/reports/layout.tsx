"use client";

import { ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const reportLinks = [
  { href: "/reports", label: "Units Over Time" },

  {
    href: "/reports/history-changes",
    label: "Changes Over Time",
  },
  { href: "/reports/drilldown", label: "Drilldown" },
  { href: "/reports/statistical-variables", label: "Variables Over Time" },
];

export default function ReportsLayout({
  children,
}: {
  readonly children: ReactNode;
}) {
  const pathname = usePathname();

  return (
    // clip, not hidden: hidden makes main a scroll box of its own, so a sticky map inside a
    // report would stick to main instead of staying in the window's view.
    <main className="flex w-full overflow-x-clip">
      <aside className="bg-gray-50 border-r border-gray-200 flex flex-col min-w-56">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
            Reports
          </h2>
        </div>
        <nav className="p-4 flex flex-col space-y-2">
          {reportLinks.map((link) => {
            const isActive = pathname === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                className={cn(
                  "rounded-md px-2 py-1.5 text-sm transition flex items-center gap-2",
                  isActive
                    ? "bg-gray-100 text-gray-900 font-semibold"
                    : "text-gray-600 hover:text-gray-900 hover:bg-gray-50"
                )}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>
      </aside>

      {/* The Drilldown sets its own width: a text column for its bars, the window's width when
          its regions show as a map beside their table. */}
      <section
        className={cn(
          "mx-auto p-8 md:py-12 flex-1 min-w-0",
          pathname === "/reports/drilldown" ? "max-w-screen-2xl" : "max-w-5xl"
        )}
      >
        {children}
      </section>
    </main>
  );
}
