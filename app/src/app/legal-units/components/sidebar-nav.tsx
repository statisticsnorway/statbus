'use client';
import {HTMLAttributes, ReactNode} from "react";
import {cn} from "@/lib/utils";
import Link from "next/link";
import {buttonVariants} from "@/components/ui/button";
import {usePathname} from "next/navigation";

export function SidebarLink({children, href}: { children: ReactNode, href: string }) {
  const pathname = usePathname()

  return (
    <Link
      href={href}
      className={cn(
        buttonVariants({variant: "ghost"}),
        pathname === href ? "bg-gray-50 hover:bg-gray-100" : "hover:bg-transparent hover:underline",
        "justify-start"
      )}
    >
      {children}
    </Link>
  )
}

export function SidebarNav({children, className}: { children?: ReactNode } & HTMLAttributes<HTMLElement>) {
  return (
    <nav className={cn("flex space-x-2 lg:flex-col lg:space-x-0 lg:space-y-1", className)}>
      {children}
    </nav>
  )
}