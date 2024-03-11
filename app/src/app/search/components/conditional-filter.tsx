import {Button} from "@/components/ui/button";
import {PlusCircle} from "lucide-react";
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover";
import {Command} from "cmdk";
import * as React from "react";
import {useCallback, useState} from "react";
import {Separator} from "@/components/ui/separator";
import {Input} from "@/components/ui/input";
import {Select, SelectContent, SelectItem, SelectTrigger, SelectValue} from "@/components/ui/select";
import {ConditionalValueBadge} from "@/app/search/components/conditional-value-badge";

interface ITableFilterCustomProps {
    title: string,
    selected?: {
        operator?: PostgrestOperator,
        value: string | null
    }
    onChange: ({value, operator}: ConditionalValue) => void,
    onReset: () => void,
}

export function ConditionalFilter(
    {
        title,
        selected,
        onChange,
        onReset
    }: ITableFilterCustomProps) {

    const [operator, setOperator] = useState<PostgrestOperator | null>(selected?.operator ?? null)
    const [value, setValue] = useState<string | null>(selected?.value ?? null)

    const updateFilter = useCallback(() => {
        if (!value || !operator) return
        onChange({operator, value})
    }, [operator, value, onChange])

    return (
        <Popover>
            <PopoverTrigger asChild>
                <Button variant="outline" size="sm" className="border-dashed h-10 space-x-2 m-2">
                    <PlusCircle className="mr-2 h-4 w-4"/>
                    {title}
                    {selected?.value && selected.operator ? (
                        <>
                            <Separator orientation="vertical" className="h-1/2"/>
                            <ConditionalValueBadge operator={selected.operator} value={selected.value}/>
                        </>
                    ) : null}
                </Button>
            </PopoverTrigger>
            <PopoverContent className="w-auto max-w-[350px] md:max-w-[500px] p-0" align="start">
                <Command className="flex p-2 space-x-2">
                    <Select
                        value={operator ?? ""}
                        onValueChange={(value) => setOperator(value as PostgrestOperator)}
                    >
                        <SelectTrigger className="w-auto max-w-[180px] space-x-2">
                            <SelectValue placeholder="Condition"/>
                        </SelectTrigger>
                        <SelectContent>
                            <SelectItem value="eq">Equal to</SelectItem>
                            <SelectItem value="gt">Greater than</SelectItem>
                            <SelectItem value="lt">Less than</SelectItem>
                            <SelectItem value="in">In list</SelectItem>
                        </SelectContent>
                    </Select>
                    <Input
                        className="w-auto max-w-[80px]"
                        value={value ?? ""}
                        onChange={(e) =>
                            setValue(e.target.value.trim())
                        }
                    />
                    <Button onClick={updateFilter} variant="outline">OK</Button>
                </Command>
                {
                    selected?.value && selected.operator ? (
                        <div className="w-full p-2">
                            <Button onClick={onReset} variant="outline" className="w-full">Clear</Button>
                        </div>
                    ) : null
                }
            </PopoverContent>
        </Popover>
    )
}
