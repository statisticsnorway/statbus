"use client";

import { Check, ChevronsUpDown } from "lucide-react";

import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Label } from "../ui/label";
import {  useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

interface Option {
  value: number | string;
  label: string;
}

interface SelectFormFieldProps {
  name: string;
  label: string;
  options: Option[];
  value?: string | number | null;
  placeholder?: string;
  readonly?: boolean;
}

export function SelectFormField({
  name,
  label,
  options,
  value,
  placeholder = "Select an option...",
  readonly,
}: SelectFormFieldProps) {
  const [open, setOpen] = useState(false);
  const [selectedValue, setSelectedValue] = useState(value ?? "");

  useGuardedEffect(
    () => {
      setSelectedValue(value ?? "");
    },
    [value],
    "SelectFormField:syncvalue"
  );

  const currentOption = options.find(
    (option) => option.value === selectedValue
  );

  return (
    <div className="flex flex-col space-y-2">
      <Label className="flex flex-col space-y-2">
        <span className="text-xs uppercase text-gray-600">{label}</span>
      </Label>
      <input type="hidden" name={name} value={selectedValue} />
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            variant="outline"
            role="combobox"
            aria-expanded={open}
            className="w-full justify-between font-medium disabled:opacity-80"
            disabled={readonly}
          >
            <span className="truncate">
              {currentOption?.label ?? `${!readonly ? placeholder : ""}`}
            </span>
            <ChevronsUpDown
              className={`ml-2 h-4 w-4 shrink-0  ${readonly ? "opacity-0" : "opacity-50"}`}
            />
          </Button>
        </PopoverTrigger>
        <PopoverContent
          className="w-(--radix-popover-trigger-width) p-0"
          align="start"
        >
          <Command>
            <CommandInput placeholder="Search..." />
            <CommandList>
              <CommandEmpty>No results found.</CommandEmpty>
              <CommandGroup>
                {options.map((option) => (
                  <CommandItem
                    key={option.value}
                    value={option.label}
                    onSelect={() => {
                      setSelectedValue(option.value);
                      setOpen(false);
                    }}
                  >
                    <Check
                      className={cn(
                        "mr-2 h-4 w-4",
                        selectedValue === option.value
                          ? "opacity-100"
                          : "opacity-0"
                      )}
                    />
                    {option.label}
                  </CommandItem>
                ))}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
    </div>
  );
}
