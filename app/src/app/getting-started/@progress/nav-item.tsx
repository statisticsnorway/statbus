"use client";
import Link from "next/link";
import { Check } from "lucide-react";
import { usePathname } from "next/navigation";

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
      <div className="flex items-center gap-2">
        <Link href={href} className={active ? "font-semibold" : "font-normal"}>
          {title}
        </Link>
        {done && <Check className="w-5 h-5" />}
      </div>
      {subtitle && <span className="text-xs">{subtitle}</span>}
    </>
  );
};
