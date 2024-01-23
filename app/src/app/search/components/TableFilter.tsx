import {Button} from "@/components/ui/button";
import {Check, PlusCircle} from "lucide-react";
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover";
import {Command} from "cmdk";
import {CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList} from "@/components/ui/command";
import * as React from "react";
import {Separator} from "@/components/ui/separator";
import {Badge} from "@/components/ui/badge";
import type {SearchFilterOption, SearchFilterValue} from "@/app/search/search.types";

interface ITableFilterProps {
    title: string,
    options?: SearchFilterOption[]
    selectedValues: SearchFilterValue[],
    onToggle: (option: SearchFilterOption) => void,
    onReset: () => void,
}

export function TableFilter({title, options = [], selectedValues, onToggle, onReset}: ITableFilterProps) {
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
                                        <Badge variant="secondary" key={option.value}
                                               className="rounded-sm px-1 font-normal">
                                            {option.value}
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
                                    <CommandItem key={option.value} onSelect={() => onToggle(option)}
                                                 className="space-x-2">
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
