import { Button } from "@/components/ui/button";
import { Check, PlusCircle } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import * as React from "react";
import { Separator } from "@/components/ui/separator";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { SearchFilterOption } from "../search";

interface ITableFilterProps {
  title: string;
  options: SearchFilterOption[];
  selectedValues: (string | null)[];
  onToggle: (option: SearchFilterOption) => void;
  onReset: () => void;
  className?: string;
}

export function OptionsFilter({
  title,
  options,
  selectedValues,
  onToggle,
  onReset,
  className,
}: ITableFilterProps) {
  if (options.length === 0) {
    return null;
  }

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className={cn("space-x-2 border-dashed", className)}
        >
          <PlusCircle className="mr-2 h-4 w-4" />
          {title}
          {selectedValues.length ? (
            <>
              <Separator orientation="vertical" className="h-1/2" />
              {options
                .filter((option) => selectedValues.includes(option.value))
                .map((option) => (
                  <Badge
                    variant="secondary"
                    key={option.value}
                    title={option.humanReadableValue ?? option.value ?? ""}
                    className={cn(
                      "rounded-sm px-2 font-normal max-w-32 overflow-auto scrollbar-hide",
                      option.className
                    )}
                  >
                    {option.icon && <span className="mr-1">{option.icon}</span>}
                    {option.humanReadableValue ?? option.value}
                  </Badge>
                ))}
            </>
          ) : null}
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
              {options.map((option) => (
                <CommandItem
                  key={`${option.value}_${option.label}`}
                  value={option.label}
                  onSelect={() => onToggle(option)}
                  className="space-x-2"
                >
                  {selectedValues.includes(option.value) ? (
                    <Check size={14} />
                  ) : null}
                  {option.icon}
                  <span>{option.label}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
        {selectedValues.length ? (
          <div className="w-full p-2">
            <Button onClick={onReset} variant="outline" className="w-full">
              Clear
            </Button>
          </div>
        ) : null}
      </PopoverContent>
    </Popover>
  );
}
