"use client";
import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { Download } from "lucide-react";
import { cn } from "@/lib/utils";

import { useSearchContext } from "@/app/search/use-search-context";

export function ExportCSVLink() {
  const { searchResult, derivedUrlSearchParams: searchParams } = useSearchContext();

  if (!searchResult?.count) {
    return null;
  }

  return (
    <Link
      target="_blank"
      prefetch={false}
      href={`/api/search/export?${searchParams}`}
      className={cn(
        buttonVariants({ variant: "secondary", size: "sm" }),
        "flex items-center space-x-2"
      )}
    >
      <Download size={17} />
      <span>Export as CSV</span>
    </Link>
  );
}
