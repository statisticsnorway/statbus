"use client";

import { cn } from "@/lib/utils";
import { useRegionContext } from "./use-region-context";

export const RegionResultCount = ({
  className,
}: {
  readonly className?: string;
}) => {
  const {
    regions: { pagination },
    regionsResult,
  } = useRegionContext();
  const hasResults = regionsResult?.count;
  const startIndex = hasResults
    ? (pagination.pageNumber - 1) * pagination.pageSize + 1
    : 0;
  const endIndex = hasResults
    ? Math.min(pagination.pageNumber * pagination.pageSize, regionsResult.count)
    : 0;
  return (
    <span className={cn("indent-2.5", className)}>
      Showing {startIndex}-{endIndex} of total {regionsResult?.count} results
    </span>
  );
};
