"use client";
import { Button } from "@/components/ui/button";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAtomValue, useSetAtom } from "jotai";
import { filtersAtom, queryAtom, resetSearchStateAtom } from "@/atoms/search";

interface ResetFilterButtonProps {
  className?: string;
}

/**
 * Clear filters (owner 2026-11-27): a quiet text button that empties the search (its filters,
 * name, sort and page), shown only while something narrows it, so it never reads as a filter in
 * effect. A filter narrows the search when it has a value: what the URL writer would write
 * (useSearchUrlSync: neither undefined nor an empty list; [null] is "Missing", a value).
 */
export const ResetFilterButton = ({ className }: ResetFilterButtonProps) => {
  const resetSearch = useSetAtom(resetSearchStateAtom);
  const filters = useAtomValue(filtersAtom);
  const query = useAtomValue(queryAtom);
  const narrowed =
    query.trim() !== "" ||
    Object.values(filters).some(
      (value) =>
        value !== undefined && !(Array.isArray(value) && value.length === 0)
    );
  if (!narrowed) return null;
  return (
    <Button
      onClick={resetSearch}
      type="button"
      variant="ghost"
      size="sm"
      className={cn("h-9 px-2 text-gray-600 hover:text-gray-900", className)}
      data-clear-filters=""
    >
      <X className="h-4 w-4" />
      Clear filters
    </Button>
  );
};
