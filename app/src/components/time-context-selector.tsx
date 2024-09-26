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
import { useTimeContext } from "@/app/use-time-context";
import { useEffect, useState } from "react";

export default function TimeContextSelector({
  className,
  title = "Select time",
}: {
  readonly className?: string;
  readonly title?: string;
}) {
  const [visible, setVisible] = useState(false);
  const { selectedTimeContext, timeContexts: time_contexts, setSelectedTimeContext} = useTimeContext();

  useEffect(() => {
    setVisible(true);
  }, []);

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className={cn(
            "space-x-2 transition-opacity border-dashed duration-500 bg-transparent",
            className,
            visible ? "opacity-100" : "opacity-0"
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
              {time_contexts.map((time_context) => (
                <CommandItem
                  key={time_context.ident}
                  value={time_context.ident!}
                  onSelect={() => setSelectedTimeContext(time_context)}
                  className="space-x-2"
                >
                  {selectedTimeContext === time_context ? <Check size={14} /> : null}
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
