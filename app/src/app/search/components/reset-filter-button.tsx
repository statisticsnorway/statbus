"use client";
import { Button } from "@/components/ui/button";
import { SearchX } from "lucide-react";
import { cn } from "@/lib/utils";
import { useSearchContext } from "@/app/search/use-search-context";

interface ResetFilterButtonProps {
  className?: string;
}

export const ResetFilterButton = ({ className }: ResetFilterButtonProps) => {
  const { dispatch } = useSearchContext();
  return (
    <Button
      onClick={() => dispatch({ type: "reset_all" })}
      type="button"
      variant="secondary"
      className={cn("flex items-center space-x-2 h-9 p-2", className)}
    >
      <SearchX size={17} />
      <span>Reset Search</span>
    </Button>
  );
};
