"use client";

import { HTMLAttributes, ReactNode } from "react";
import { cn } from "@/lib/utils";
import { usePathname, useSearchParams } from "next/navigation";
import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";

export function SidebarLink({
  children,
  href,
}: {
  readonly children: ReactNode;
  readonly href: string;
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const url = params ? `${href}?${params}` : href;

  return (
    <Link
      href={url}
      className={cn(
        buttonVariants({ variant: "ghost" }),
        pathname === href
          ? "bg-gray-100 hover:bg-gray-200"
          : "hover:bg-transparent hover:underline",
        "justify-start"
      )}
    >
      {children}
    </Link>
  );
}

export function SidebarNav({
  children,
  className,
}: { children?: ReactNode } & HTMLAttributes<HTMLElement>) {
  return (
    <nav
      className={cn(
        "flex space-x-2 lg:flex-col lg:space-x-0 lg:space-y-1",
        className
      )}
    >
      {children}
    </nav>
  );
}
