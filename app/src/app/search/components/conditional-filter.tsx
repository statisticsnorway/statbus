import { Button } from "@/components/ui/button";
import { PlusCircle } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import * as React from "react";
import { useCallback, useState } from "react";
import { Separator } from "@/components/ui/separator";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ConditionalValueBadge } from "@/app/search/components/conditional-value-badge";
import { cn } from "@/lib/utils";
import { Command } from "@/components/ui/command";

interface ITableFilterCustomProps {
  title: string;
  selected?: {
    operator?: string;
    value: string | null;
  };
  onChange: ({ value, operator }: ConditionalValue) => void;
  onReset: () => void;
  className?: string;
}

export function ConditionalFilter({
  title,
  selected,
  onChange,
  onReset,
  className,
}: ITableFilterCustomProps) {
  const [operator, setOperator] = useState<string | null>(
    selected?.operator ?? null
  );
  const [value, setValue] = useState<string | null>(selected?.value ?? null);

  const updateFilter = useCallback(() => {
    if (!value || !operator) return;
    onChange({ operator, value });
  }, [operator, value, onChange]);

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className={cn("space-x-2 border-dashed", className)}
        >
          <PlusCircle className="mr-2 h-4 w-4" />
          {title}
          {selected?.value && selected.operator ? (
            <>
              <Separator orientation="vertical" className="h-1/2" />
              <ConditionalValueBadge
                operator={selected.operator}
                value={selected.value}
              />
            </>
          ) : null}
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="w-auto max-w-[350px] p-0 md:max-w-[500px]"
        align="start"
      >
        <Command className="flex space-x-2 p-2">
          <Select
            value={operator ?? ""}
            onValueChange={(value) => setOperator(value)}
          >
            <SelectTrigger className="w-auto max-w-[180px] space-x-2">
              <SelectValue placeholder="Condition" />
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
            onChange={(e) => setValue(e.target.value.trim())}
          />
          <Button onClick={updateFilter} variant="outline">
            OK
          </Button>
        </Command>
        {selected?.value && selected.operator ? (
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
