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
import { useTimeFrame } from "@/atoms/app-derived";
import { useState } from "react";
import { groupTimeFrames } from "@/lib/time-frame";
import { TimeFrameGroupHeading } from "@/components/time-frame-group-heading";

/** The frame menu: the live frame, the relative frames and the fixed frames (lib/time-frame.ts). */
export default function TimeFrameSelector({
  className,
  title = "Select time frame",
}: {
  readonly className?: string;
  readonly title?: string;
}) {
  const { selectedTimeFrame, setSelectedTimeFrame, timeFrames } = useTimeFrame();
  const [isPopoverOpen, setIsPopoverOpen] = useState(false);
  const groups = groupTimeFrames(timeFrames, { forMenu: true });

  return (
    <Popover open={isPopoverOpen} onOpenChange={setIsPopoverOpen}>
      <PopoverTrigger asChild onClick={() => setIsPopoverOpen(!isPopoverOpen)}>
        <Button
          variant="outline"
          className={cn(
            "space-x-2 border-dashed bg-transparent",
            className
          )}
          data-time-frame-ident={selectedTimeFrame?.ident ?? undefined}
          data-time-frame-valid-on={selectedTimeFrame?.valid_on ?? undefined}
        >
          <CalendarClock className="mr-2 h-4 w-4" />
          {selectedTimeFrame?.name ?? title}
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
            {groups.map((group) => (
              <CommandGroup key={group.kind} heading={<TimeFrameGroupHeading group={group} />}>
                {group.frames.map((timeFrame) => (
                  <CommandItem
                    key={timeFrame.ident!}
                    value={`${timeFrame.name} ${timeFrame.ident}`}
                    onSelect={() => {
                      setSelectedTimeFrame(timeFrame);
                      setIsPopoverOpen(false);
                    }}
                    className="space-x-2"
                  >
                    {selectedTimeFrame?.ident === timeFrame.ident ? (
                      <Check size={14} />
                    ) : null}
                    <span>{timeFrame.name}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            ))}
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
