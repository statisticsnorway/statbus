"use client";
import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { Download } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAtomValue } from 'jotai';
import { searchResultAtom, derivedApiSearchParamsAtom } from '@/atoms/search';

export function ExportCSVLink() {
  const searchResult = useAtomValue(searchResultAtom);
  const searchParams = useAtomValue(derivedApiSearchParamsAtom);

  if (!searchResult?.total) {
    return null;
  }

  return (
    <Link
      target="_blank"
      prefetch={false}
      href={`/api/search/export?${searchParams.toString()}`}
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
