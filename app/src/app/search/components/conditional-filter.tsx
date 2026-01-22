import { Button } from "@/components/ui/button";
import { PlusCircle, X } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import * as React from "react";
import { useCallback, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
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
import { ConditionalValue, Condition } from "../search";

interface ITableFilterCustomProps {
  title: string;
  selected: ConditionalValue | null;
  onChange: (value: ConditionalValue) => void;
  onReset: () => void;
  className?: string;
}

// Helper to normalize ConditionalValue to array of Conditions
function toConditionsArray(value: ConditionalValue | null): Condition[] {
  if (!value) return [];
  if ('conditions' in value) return value.conditions;
  return [value];
}

// Helper to normalize array of Conditions to ConditionalValue
function fromConditionsArray(conditions: Condition[]): ConditionalValue | null {
  if (conditions.length === 0) return null;
  if (conditions.length === 1) return conditions[0];
  return { conditions };
}

export function ConditionalFilter({
  title,
  selected,
  onChange,
  onReset,
  className,
}: ITableFilterCustomProps) {
  const [isPopoverOpen, setIsPopoverOpen] = useState(false);
  const [conditions, setConditions] = useState<Condition[]>(() => 
    toConditionsArray(selected).length > 0 
      ? toConditionsArray(selected) 
      : [{ operator: 'eq', operand: '' }]
  );

  const updateFilter = useCallback(() => {
    // Filter out empty conditions
    const validConditions = conditions.filter(c => c.operand.trim() !== '');
    if (validConditions.length === 0) return;
    
    const value = fromConditionsArray(validConditions);
    if (value) {
      onChange(value);
      setIsPopoverOpen(false);
    }
  }, [conditions, onChange]);

  const addCondition = useCallback(() => {
    setConditions([...conditions, { operator: 'eq', operand: '' }]);
  }, [conditions]);

  const removeCondition = useCallback((index: number) => {
    const newConditions = conditions.filter((_, i) => i !== index);
    // Keep at least one condition row
    if (newConditions.length === 0) {
      setConditions([{ operator: 'eq', operand: '' }]);
    } else {
      setConditions(newConditions);
    }
  }, [conditions]);

  const updateCondition = useCallback((index: number, field: 'operator' | 'operand', value: string) => {
    const newConditions = [...conditions];
    newConditions[index] = { ...newConditions[index], [field]: value };
    setConditions(newConditions);
  }, [conditions]);

  useGuardedEffect(() => {
    const selectedConditions = toConditionsArray(selected);
    if (selectedConditions.length > 0) {
      setConditions(selectedConditions);
    } else {
      setConditions([{ operator: 'eq', operand: '' }]);
    }
  }, [selected], 'ConditionalFilter:syncStateFromSelected');

  const hasValue = toConditionsArray(selected).some(c => c.operand.trim() !== '');

  return (
    <Popover open={isPopoverOpen} onOpenChange={setIsPopoverOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className={cn("space-x-2 border-dashed", className)}
        >
          <PlusCircle className="mr-2 h-4 w-4" />
          {title}
          {hasValue ? (
            <>
              <Separator orientation="vertical" className="h-1/2" />
              <ConditionalValueBadge value={selected!} />
            </>
          ) : null}
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="w-auto max-w-[400px] p-0 md:max-w-[600px]"
        align="start"
      >
        <div className="p-2 space-y-2">
          {conditions.map((condition, index) => (
            <div key={index} className="flex flex-col gap-2">
              {index > 0 && (
                <div className="text-xs text-muted-foreground text-center font-medium">
                  AND
                </div>
              )}
              <Command className="flex flex-row justify-between gap-2">
                <Select
                  value={condition.operator}
                  onValueChange={(value) => updateCondition(index, 'operator', value)}
                >
                  <SelectTrigger className="w-auto max-w-[180px] space-x-2">
                    <SelectValue placeholder="Operator" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="eq">=</SelectItem>
                    <SelectItem value="gt">&gt;</SelectItem>
                    <SelectItem value="gte">≥</SelectItem>
                    <SelectItem value="lt">&lt;</SelectItem>
                    <SelectItem value="lte">≤</SelectItem>
                    <SelectItem value="in">in</SelectItem>
                  </SelectContent>
                </Select>
                <Input
                  className="w-auto max-w-[100px]"
                  value={condition.operand}
                  onChange={(e) => updateCondition(index, 'operand', e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      updateFilter();
                    }
                  }}
                  placeholder="value"
                />
                {conditions.length > 1 && (
                  <Button
                    onClick={() => removeCondition(index)}
                    variant="ghost"
                    size="sm"
                    className="h-9 w-9 p-0"
                  >
                    <X className="h-4 w-4" />
                  </Button>
                )}
              </Command>
            </div>
          ))}
          
          <div className="flex gap-2 pt-1">
            <Button
              onClick={addCondition}
              variant="outline"
              size="sm"
              className="flex-1"
            >
              + Add
            </Button>
            <Button onClick={updateFilter} variant="default" size="sm" className="flex-1">
              Apply
            </Button>
          </div>

          {hasValue && (
            <Button onClick={onReset} variant="outline" size="sm" className="w-full">
              Clear
            </Button>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}
