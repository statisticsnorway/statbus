"use client";
import { CalendarClock, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { useTimeContext } from "@/atoms/hooks";
import { useState } from "react";

export default function TimeContextSelector({
  className,
  title = "Select time",
}: {
  readonly className?: string;
  readonly title?: string;
}) {
  const { selectedTimeContext, setSelectedTimeContext, timeContexts } = useTimeContext();
  const [isPopoverOpen, setIsPopoverOpen] = useState(false);


  return (
    <Popover open={isPopoverOpen} onOpenChange={setIsPopoverOpen}>
      <PopoverTrigger asChild onClick={() => setIsPopoverOpen(!isPopoverOpen)}>
        <Button
          variant="outline"
          className={cn(
            "space-x-2 border-dashed bg-transparent",
            className
          )}
        >
          <CalendarClock className="mr-2 h-4 w-4" />
          {selectedTimeContext?.name_when_query ?? title}
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
              {timeContexts.map((time_context) => (
                <CommandItem
                  key={time_context.ident}
                  value={time_context.ident!}
                  onSelect={() => {
                    setSelectedTimeContext(time_context);
                    setIsPopoverOpen(false);
                  }}
                  className="space-x-2"
                >
                  {selectedTimeContext?.ident === time_context?.ident ? <Check size={14} /> : null}
                  <span>{time_context.name_when_query}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
