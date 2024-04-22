"use client";

import { Button } from "@/components/ui/button";
import { useRegionContext } from "./use-region-context";
import { cn } from "@/lib/utils";
import { SearchX } from "lucide-react";

interface ResetFilterButtonProps {
  className?: string;
}

export const ResetFilterButton = ({ className }: ResetFilterButtonProps) => {
  const { dispatch } = useRegionContext();
  return (
    <Button
      onClick={() => dispatch({ type: "reset_search" })}
      type="button"
      variant="secondary"
      className={cn("flex items-center space-x-2 h-9 p-2", className)}
    >
      <SearchX size={17} />
      <span>Reset Search</span>
    </Button>
  );
};
