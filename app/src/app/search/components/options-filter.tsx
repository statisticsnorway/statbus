import {Button} from "@/components/ui/button";
import {Check, PlusCircle} from "lucide-react";
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover";
import {Command} from "cmdk";
import {CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList} from "@/components/ui/command";
import * as React from "react";
import {Separator} from "@/components/ui/separator";
import {Badge} from "@/components/ui/badge";
import type {SearchFilterOption} from "@/app/search/search.types";
import {cn} from "@/lib/utils";

interface ITableFilterProps {
  title: string,
  options?: SearchFilterOption[]
  selectedValues: string[],
  onToggle: (option: SearchFilterOption) => void,
  onReset: () => void,
}

export function OptionsFilter({title, options = [], selectedValues, onToggle, onReset}: ITableFilterProps) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className="border-dashed h-10 space-x-2 m-2">
          <PlusCircle className="mr-2 h-4 w-4"/>
          {title}
          {selectedValues?.length ? (
            <>
              <Separator orientation="vertical" className="h-1/2"/>
              {
                options
                  .filter((option) => selectedValues.includes(option.value))
                  .map((option) => (
                    <Badge variant="secondary" key={option.value} className={cn("rounded-sm px-2 font-normal", option.className)}>
                      {option.humanReadableValue ?? option.value}
                    </Badge>
                  ))
              }
            </>
          ) : null}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-auto max-w-[350px] md:max-w-[500px] p-0" align="start">
        <Command>
          <CommandInput placeholder={title}/>
          <CommandList>
            <CommandEmpty>No results found.</CommandEmpty>
            <CommandGroup>
              {
                options.map((option) => (
                  <CommandItem key={`${option.value}_${option.label}`} onSelect={() => onToggle(option)} className="space-x-2">
                    {selectedValues.includes(option.value) ? <Check size={14}/> : null}
                    <span>{option.label}</span>
                  </CommandItem>
                ))
              }
            </CommandGroup>
          </CommandList>
        </Command>
        {
          selectedValues.length ? (
            <div className="w-full p-2">
              <Button onClick={onReset} variant="outline" className="w-full">Clear</Button>
            </div>
          ) : null
        }
      </PopoverContent>
    </Popover>
  )
}
