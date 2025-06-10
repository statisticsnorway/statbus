"use client";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { MoreHorizontal, ShoppingBasket } from "lucide-react";
import { StatisticalUnit } from "@/atoms/index"; 
import { useSelection } from "@/atoms/hooks"; // Changed to Jotai hook

export default function SearchResultTableRowDropdownMenu({
  unit,
}: {
  readonly unit: StatisticalUnit;
}) {
  const { toggle, selected } = useSelection(); // Use Jotai hook
  const isInBasket = selected.some(
    (s) => s.unit_id === unit.unit_id && s.unit_type === unit.unit_type
  );
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" className="inline-block" title="Select action">
          <MoreHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent className="w-56">
        <DropdownMenuLabel>{unit.name}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuGroup>
          <DropdownMenuItem onClick={() => toggle(unit)}>
            <ShoppingBasket className="mr-2 h-4 w-4" />
            <span>
              {isInBasket ? "Remove from selection" : "Add to selection"}
            </span>
          </DropdownMenuItem>
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
