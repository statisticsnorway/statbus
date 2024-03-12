"use client";
import Link from "next/link";
import { Check } from "lucide-react";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

export const NavItem = ({
  title,
  href,
  done,
  subtitle,
}: {
  readonly title: string;
  readonly subtitle?: string;
  readonly href: string;
  readonly done?: boolean;
}) => {
  const pathname = usePathname();
  const active = pathname === href;

  return (
    <>
      <div className="flex items-center gap-2 justify-between">
        <Link
          href={href}
          className={cn("flex-1", active ? "font-semibold" : "font-normal")}
        >
          {title}
        </Link>
        {done && <Check className="w-5 h-5" />}
      </div>
      {done && subtitle && (
        <span className="text-xs text-gray-700">{subtitle}</span>
      )}
    </>
  );
};
