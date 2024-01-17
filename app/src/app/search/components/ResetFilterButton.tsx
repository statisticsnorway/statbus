import {Button} from "@/components/ui/button";
import {X} from "lucide-react";

export const ResetFilterButton = ({onReset}: { onReset: () => void }) => (
  <Button
    variant="ghost"
    className="px-2 h-10 w-10"
    onClick={onReset}
  >
    <X size={18}/>
  </Button>
)
