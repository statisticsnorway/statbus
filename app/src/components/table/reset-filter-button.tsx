import { Button } from "@/components/ui/button";
import { SearchX } from "lucide-react";
interface ResetFilterButtonProps {
  onReset: () => void;
}
const ResetFilterButton = ({ onReset }: ResetFilterButtonProps) => {
  return (
    <Button
      onClick={onReset}
      type="button"
      variant="secondary"
      className="flex items-center space-x-2 h-9 p-2"
    >
      <SearchX size={17} />
      <span>Reset Search</span>
    </Button>
  );
};
export default ResetFilterButton;
