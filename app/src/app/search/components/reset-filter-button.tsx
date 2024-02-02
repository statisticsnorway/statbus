import {Button} from "@/components/ui/button";
import {X} from "lucide-react";
import {cn} from "@/lib/utils";

interface ResetFilterButtonProps {
  onReset: () => void;
  className?: string;
}

export const ResetFilterButton = ({onReset, className}: ResetFilterButtonProps) => (
  <Button
    variant="secondary"
    className={cn("space-x-1 flex items-center h-10 bg-amber-200", className)}
    onClick={onReset}
  >
    <span>Reset Search</span>
    <X size={18}/>
  </Button>
)
