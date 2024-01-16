import {Button} from "@/components/ui/button";
import {Check, PlusCircle} from "lucide-react";
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover";
import {Command} from "cmdk";
import {
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator
} from "@/components/ui/command";
import * as React from "react";
import {Separator} from "@/components/ui/separator";
import {Badge} from "@/components/ui/badge";

interface ITableFilterOption {
  label: string,
  value: string
}

interface ITableFilterProps {
  title: string,
  options: ITableFilterOption[]
  selectedOptionValues: Set<string>,
  onToggle: (option: ITableFilterOption) => void,
  onReset: () => void,
}

export function TableFilter({title, options, selectedOptionValues, onToggle, onReset}: ITableFilterProps) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className="border-dashed h-full space-x-3">
          <PlusCircle className="mr-2 h-4 w-4"/>
          {title}
          {selectedOptionValues?.size ? (
            <>
              <Separator orientation="vertical" className="h-1/2"/>
              {
                options
                  .filter((option) => selectedOptionValues.has(option.value))
                  .map((option) => (
                    <Badge variant="secondary" key={option.value} className="rounded-sm px-1 font-normal">
                      {option.label}
                    </Badge>
                  ))
              }
            </>
          ) : null}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-auto p-0" align="start">
        <Command>
          <CommandInput placeholder={title}/>
          <CommandList>
            <CommandEmpty>No results found.</CommandEmpty>
            <CommandGroup>
              {
                options.map((option) => (
                  <CommandItem key={option.value} onSelect={() => onToggle(option)} className="space-x-2">
                    {selectedOptionValues.has(option.value) ? <Check size={14}/> : null}
                    <span>{option.label}</span>
                  </CommandItem>
                ))
              }
            </CommandGroup>
            {
              selectedOptionValues?.size ? (
                <>
                  <CommandSeparator/>
                  <CommandGroup heading="Reset">
                    <CommandItem onSelect={onReset}>Clear all</CommandItem>
                  </CommandGroup>
                </>
              ) : null
            }
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
