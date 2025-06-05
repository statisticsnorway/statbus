"use client";
import Link from "next/link";
import { Check, Loader2 } from "lucide-react";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { ReactNode } from "react";

export const NavItem = ({
  title,
  href,
  done,
  subtitle,
  processing,
  icon,
}: {
  readonly title: string;
  readonly subtitle?: string;
  readonly href: string;
  readonly done?: boolean;
  readonly processing?: boolean;
  readonly icon?: ReactNode;
}) => {
  const pathname = usePathname();
  const active = pathname === href;

  return (
    <>
      <div className="flex items-center gap-2 justify-between">
        <Link
          href={href}
          className={cn("flex-1 flex items-center gap-2", active ? "font-semibold" : "font-normal")}
        >
          {icon && <span className="text-gray-500">{icon}</span>}
          {title}
        </Link>
        {processing ? (
          <Loader2 className="w-5 h-5 text-yellow-500 animate-spin" />
        ) : (
          done && <Check className="w-5 h-5" />
        )}
      </div>
      {(done || processing) && subtitle && (
        <span className="text-xs text-gray-700">{subtitle}</span>
      )}
    </>
  );
};
