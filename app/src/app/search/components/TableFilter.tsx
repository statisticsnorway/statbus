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

interface ITableFilterProps {
  title: string,
  options: SearchFilterOption[]
  selectedValues: SearchFilterValue[],
  onToggle: (option: SearchFilterOption) => void,
  onReset: () => void,
}

export function TableFilter({title, options, selectedValues, onToggle, onReset}: ITableFilterProps) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className="border-dashed h-full space-x-2">
          <PlusCircle className="mr-2 h-4 w-4"/>
          {title}
          {selectedValues?.length ? (
            <>
              <Separator orientation="vertical" className="h-1/2"/>
              {
                options
                  .filter((option) => selectedValues.includes(option.value))
                  .map((option) => (
                    <Badge variant="secondary" key={option.value} className="rounded-sm px-1 font-normal">
                      {option.value}
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
                    {selectedValues.includes(option.value) ? <Check size={14}/> : null}
                    <span>{option.label}</span>
                  </CommandItem>
                ))
              }
            </CommandGroup>
            {
              selectedValues?.length ? (
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
