"use client";
import { buttonVariants } from "@/components/ui/button";
import { Download } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAtomValue } from 'jotai';
import { searchResultAtom, derivedApiSearchParamsAtom } from '@/atoms/search';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function ExportCSVLink() {
  const searchResult = useAtomValue(searchResultAtom);
  const searchParams = useAtomValue(derivedApiSearchParamsAtom);

  if (!searchResult?.total) {
    return null;
  }

  const baseUrl = `/api/search/export?${searchParams.toString()}`;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          buttonVariants({ variant: "secondary", size: "sm" }),
          "flex items-center space-x-2"
        )}
      >
        <Download size={17} />
        <span>Export</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem asChild>
          <a href={`${baseUrl}&format=csv`} download>Download CSV</a>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <a href={`${baseUrl}&format=xlsx`} download>Download Excel (.xlsx)</a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
