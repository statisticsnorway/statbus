import Link from "next/link";
import { cn } from "@/lib/utils";
import { ReactNode } from "react";

export interface StatisticalUnitDetailsLinkProps {
  readonly id: number;
  readonly type:
    | "power_group"
    | "enterprise"
    | "legal_unit"
    | "establishment";
  readonly children?: ReactNode;
  readonly className?: string;
  readonly sub_path?: string;
  readonly params?: string;
}

export function StatisticalUnitDetailsLink({
  id,
  type,
  children,
  className,
  sub_path,
  params,
}: StatisticalUnitDetailsLinkProps) {
  const href = {
    power_group: `/power-groups/${id}`,
    enterprise: `/enterprises/${id}`,
    legal_unit: `/legal-units/${id}`,
    establishment: `/establishments/${id}`,
  }[type];

  const path = sub_path ? `${href}/${sub_path}` : href;
  const url = params ? `${path}?${params}` : path;

  return (
    <Link href={url} className={cn("font-medium", className)}>
      {children}
    </Link>
  );
}
