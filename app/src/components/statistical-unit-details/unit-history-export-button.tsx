import { buttonVariants } from "@/components/ui/button";
import { Download } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
export function UnitHistoryExportButton({
  unitId,
  unitType,
}: {
  readonly unitId: number;
  readonly unitType: string;
}) {
  const params = new URLSearchParams({
    unit_id: `eq.${unitId}`,
    unit_type: `in.(${unitType})`,
    order: "valid_from.asc",
  });
  const baseUrl = `/api/search/export?${params.toString()}`;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          buttonVariants({ variant: "outline", size: "sm" }),
          "flex items-center space-x-2"
        )}
      >
        <Download size={17} />
        <span>Export unit history</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem asChild>
          <a href={`${baseUrl}&format=csv`} download>
            Download CSV
          </a>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <a href={`${baseUrl}&format=xlsx`} download>
            Download Excel (.xlsx)
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
