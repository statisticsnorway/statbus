"use client";
import { Button } from "@/components/ui/button";
import { SearchX } from "lucide-react";
import { cn } from "@/lib/utils";
import { useSetAtom } from 'jotai';
import { resetSearchStateAtom } from '@/atoms/search'; // Assuming index.ts is resolved by default

interface ResetFilterButtonProps {
  className?: string;
}

export const ResetFilterButton = ({ className }: ResetFilterButtonProps) => {
  const resetSearch = useSetAtom(resetSearchStateAtom);
  return (
    <Button
      onClick={resetSearch}
      type="button"
      variant="secondary"
      className={cn("flex items-center space-x-2 h-9 p-2", className)}
    >
      <SearchX size={17} />
      <span>Reset Search</span>
    </Button>
  );
};
