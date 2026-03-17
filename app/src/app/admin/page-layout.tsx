import Link from "next/link";
import { ReactNode } from "react";
import { ChevronRight } from "lucide-react";

export default function AdminPageLayout({
  title,
  subtitle,
  children,
}: {
  readonly title: string;
  readonly subtitle: string;
  readonly children: ReactNode;
}) {
  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col px-2 py-8 md:py-12">
      <div className="space-y-4">
        <div className="mb-3 flex items-center">
          <Link
            href="/admin"
            className="hover:underline text-gray-500 text-2xl"
          >
            Admin
          </Link>
          <ChevronRight className="h-6 w-6 text-gray-400" />
          <span className="text-2xl ">{title}</span>
        </div>
        <div>
          <p>{subtitle}</p>
        </div>
        {children}
      </div>
    </main>
  );
}
