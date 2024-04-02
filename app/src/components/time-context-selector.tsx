"use client";
import { useTimeContext } from "@/app/time-context";
import { CalendarClock, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import { Command } from "cmdk";
import {
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import * as React from "react";

export default function TimeContextSelector({
  className,
  title = "Select period",
}: {
  readonly className?: string;
  readonly title?: string;
}) {
  const { selectedPeriod, periods, setSelectedPeriod } = useTimeContext();

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className={cn(
            "space-x-2 transition-opacity duration-500 bg-transparent",
            className,
            !selectedPeriod ? "opacity-0" : "opacity-100"
          )}
        >
          <CalendarClock className="mr-2 h-4 w-4" />
          {selectedPeriod?.name}
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="w-auto max-w-[350px] p-0 md:max-w-[500px]"
        align="start"
      >
        <Command>
          <CommandInput placeholder={title} />
          <CommandList>
            <CommandEmpty>No results found.</CommandEmpty>
            <CommandGroup>
              {periods.map((period) => (
                <CommandItem
                  key={period.type}
                  value={period.type!}
                  onSelect={() => setSelectedPeriod(period)}
                  className="space-x-2"
                >
                  {selectedPeriod === period ? <Check size={14} /> : null}
                  <span>{period.name}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
