import {Button} from "@/components/ui/button";
import {PlusCircle} from "lucide-react";
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

interface TableFilterProps {
  title: string,
  options: { label: string, value: string }[]
  selected?: Set<string>
}

export function TableFilter({title, options, selected}: TableFilterProps) {

  const toggle = (option: { label: string, value: string }) => {
    console.log(`Toggle option ${option.label}`)
  }

  const reset = () => {
    console.log("Reset filter")
  }

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className="border-dashed h-full space-x-3">
          <PlusCircle className="mr-2 h-4 w-4"/>
          {title}
          {selected?.size && (
            <>
              <Separator orientation="vertical" className="h-1/2"/>
              {
                options
                  .filter((option) => selected.has(option.value))
                  .map((option) => (
                    <Badge variant="secondary" key={option.value} className="rounded-sm px-1 font-normal">
                      {option.label}
                    </Badge>
                  ))
              }
            </>
          )}
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
                  <CommandItem key={option.value} onSelect={() => toggle(option)}>
                    {option.label}
                  </CommandItem>
                ))
              }
            </CommandGroup>
            {
              selected?.size && (
                <>
                  <CommandSeparator/>
                  <CommandGroup heading="Reset">
                    <CommandItem onSelect={reset}>Clear all</CommandItem>
                  </CommandGroup>
                </>
              )
            }
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
