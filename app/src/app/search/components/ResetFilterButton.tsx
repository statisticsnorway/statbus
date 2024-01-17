import {Button} from "@/components/ui/button";
import {X} from "lucide-react";

export const ResetFilterButton = ({onReset}: { onReset: () => void }) => (
  <Button
    variant="ghost"
    className="h-8 px-2 lg:px-3"
    onClick={onReset}
  >
    Reset
    <X className="ml-2 h-4 w-4"/>
  </Button>
)
