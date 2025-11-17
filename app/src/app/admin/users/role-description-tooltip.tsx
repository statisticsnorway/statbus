import { InfoIcon } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { userRoles } from "./roles";

export const RoleDescriptionTooltip = () => {
  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <span className="flex gap-1 text-xs text-gray-400 w-fit">
            <InfoIcon className="h-4 w-4 ml-2 text-gray-400" />
            What do the roles mean?
          </span>
        </TooltipTrigger>
        <TooltipContent side="bottom" align="start">
          <div className="w-full max-w-md">
            <div className="space-y-2.5">
              {userRoles.map(({ label, description }) => (
                <div key={label} className="flex flex-col text-sm ">
                  <span className="font-semibold">{label}</span>
                  <span className="text-gray-300">{description}</span>
                </div>
              ))}
            </div>
          </div>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
};
