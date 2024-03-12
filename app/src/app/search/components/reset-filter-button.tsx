import { Button } from "@/components/ui/button";
import { SearchX } from "lucide-react";
import { cn } from "@/lib/utils";

interface ResetFilterButtonProps {
  onReset: () => void;
  className?: string;
}

export const ResetFilterButton = ({
  onReset,
  className,
}: ResetFilterButtonProps) => (
  <Button
    onClick={onReset}
    type="button"
    size="sm"
    variant="secondary"
    className={cn("flex items-center space-x-2", className)}
  >
    <SearchX size={17} />
    <span>Reset Search</span>
  </Button>
);
