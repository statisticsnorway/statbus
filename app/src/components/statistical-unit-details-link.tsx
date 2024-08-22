import Link from "next/link";
import { cn } from "@/lib/utils";
import { ReactNode } from "react";
import { useSearchParams } from "next/navigation";

export interface StatisticalUnitDetailsLinkProps {
  readonly id: number;
  readonly type:
    | "enterprise_group"
    | "enterprise"
    | "legal_unit"
    | "establishment";
  readonly children?: ReactNode;
  readonly className?: string;
  readonly sub_path?: string;
}

export function StatisticalUnitDetailsLink({
  id,
  type,
  children,
  className,
  sub_path,
}: StatisticalUnitDetailsLinkProps) {
  const href = {
    enterprise_group: `/enterprise-groups/${id}`,
    enterprise: `/enterprises/${id}`,
    legal_unit: `/legal-units/${id}`,
    establishment: `/establishments/${id}`,
  }[type];

  const params = useSearchParams();
  const path = sub_path ? `${href}/${sub_path}` : href;
  const url = params ? `${path}?${params}` : path;

  return (
    <Link href={url} className={cn("font-medium", className)}>
      {children}
    </Link>
  );
}
