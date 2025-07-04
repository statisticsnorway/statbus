"use client";
import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Settings, Trash } from "lucide-react";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import * as React from "react";
import CombineUnits from "@/app/search/components/bulk-actions/combine-units";
import { useSelection } from "@/atoms/search"; // Changed to Jotai hook

export default function SearchBulkActionButton() {
  const { selected, clear } = useSelection(); // Use Jotai hook

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          disabled={!selected.length}
          variant="secondary"
          size="sm"
          className="space-x-2 border-dashed"
        >
          <Settings className="mr-2 h-4 w-4" />
          {selected.length} {selected.length === 1 ? "unit" : "units"} selected
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="w-auto max-w-[350px] p-0 md:max-w-[500px]"
        align="start"
      >
        <Command>
          <CommandInput placeholder="Select action" />
          <CommandList>
            <CommandEmpty>No command found.</CommandEmpty>
            <CommandGroup>
              <CombineUnits />
            </CommandGroup>
            <CommandGroup>
              <CommandItem onSelect={clear} className="space-x-2">
                <Trash className="h-4 w-4" />
                <span>Clear selection</span>
              </CommandItem>
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
