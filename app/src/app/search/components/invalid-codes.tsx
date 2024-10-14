import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Bug } from "lucide-react";

export function InvalidCodes({
  invalidCodes,
}: {
  readonly invalidCodes: string;
}) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <div title={invalidCodes}>
          <Bug className="h-3 w-3 stroke-gray-600" />
        </div>
      </PopoverTrigger>
      <PopoverContent className="p-1.5 w-full">
        <p className="text-xs">{invalidCodes}</p>
      </PopoverContent>
    </Popover>
  );
}
