import { Button } from "@/components/ui/button";
import { PlusCircle } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import * as React from "react";
import { useCallback, useState, useEffect } from "react";
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
import { ConditionalValue } from "../search";

interface ITableFilterCustomProps {
  title: string;
  selected: {
    operator: string;
    operand: string;
  } | null;
  onChange: ({ operand, operator }: ConditionalValue) => void;
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
  const [isPopoverOpen, setIsPopoverOpen] = useState(false);
  const [operator, setOperator] = useState<string | null>(
    selected?.operator ?? "eq"
  );
  const [operand, setOperand] = useState<string | null>(
    selected?.operand ?? null
  );

  const updateFilter = useCallback(() => {
    if (!operand || !operator) return;
    onChange({ operator, operand: operand });
    setIsPopoverOpen(false);
  }, [operator, operand, onChange]);

  useEffect(() => {
    setOperator(selected?.operator ?? "eq");
    setOperand(selected?.operand ?? "");
  }, [selected]);

  return (
    <Popover open={isPopoverOpen} onOpenChange={setIsPopoverOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className={cn("space-x-2 border-dashed", className)}
        >
          <PlusCircle className="mr-2 h-4 w-4" />
          {title}
          {selected?.operand && selected.operator ? (
            <>
              <Separator orientation="vertical" className="h-1/2" />
              <ConditionalValueBadge
                operator={selected.operator}
                operand={selected.operand}
              />
            </>
          ) : null}
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="w-auto max-w-[350px] p-0 md:max-w-[500px]"
        align="start"
      >
        <Command className="flex flex-row justify-between gap-2 p-2">
          <Select
            value={operator ?? ""}
            onValueChange={(value) => setOperator(value)}
          >
            <SelectTrigger className="w-auto max-w-[180px] space-x-2">
              <SelectValue placeholder="Condition" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="eq">=</SelectItem>
              <SelectItem value="gt">&gt;</SelectItem>
              <SelectItem value="lt">&lt;</SelectItem>
              <SelectItem value="in">In list</SelectItem>
            </SelectContent>
          </Select>
          <Input
            className="w-auto max-w-[80px]"
            value={operand ?? ""}
            onChange={(e) => setOperand(e.target.value.trim())}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                updateFilter();
              }
            }}
          />

          <Button onClick={updateFilter} variant="outline">
            OK
          </Button>
        </Command>
        {selected?.operand && selected.operator ? (
          <div className="w-full p-2 pt-0">
            <Button onClick={onReset} variant="outline" className="w-full">
              Clear
            </Button>
          </div>
        ) : null}
      </PopoverContent>
    </Popover>
  );
}
