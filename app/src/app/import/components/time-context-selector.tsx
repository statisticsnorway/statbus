"use client";

import React, { useEffect, useState } from "react";
import { useImportManager } from "@/atoms/import";
import { Label } from "@/components/ui/label";
import { Tables } from "@/lib/database.types";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { CalendarIcon, InfoIcon } from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { format } from "date-fns";
import { Calendar } from "@/components/ui/calendar";
import { Spinner } from "@/components/ui/spinner";

interface TimeContextSelectorProps {
  unitType: "legal-units" | "establishments" | "establishments-without-legal-unit";
}

export function TimeContextSelector({ unitType }: TimeContextSelectorProps) {
  const { 
    importState: { selectedDefinition, availableDefinitions, useExplicitDates, explicitStartDate, explicitEndDate },
    timeContext: { availableContexts, selectedContext },
    setSelectedTimeContext, 
    setSelectedDefinition,
    setUseExplicitDates,
    setExplicitStartDate,
    setExplicitEndDate
  } = useImportManager();

  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);

  const handleTimeContextChange = (value: string) => {
    setSelectedTimeContext(value);
  };

  const validityOptions = React.useMemo(() => {
    type ValidityOption = {
      id: string;
      label: string;
      description: string | null;
      definition: Tables<'import_definition'>;
      useExplicitDates: boolean;
    };
    const options: ValidityOption[] = [];
    const jobProvidedDef = availableDefinitions.find(d => d.valid_time_from === 'job_provided');
    if (jobProvidedDef) {
        options.push({
            id: 'job_provided_time_context',
            label: 'Apply a validity period to all records',
            description: 'Select a predefined validity period to apply to all imported records.',
            definition: jobProvidedDef,
            useExplicitDates: false,
        });
        options.push({
            id: 'job_provided_explicit_dates',
            label: 'Provide an explicit start and end date',
            description: 'These dates will be used as the default validity for all imported records.',
            definition: jobProvidedDef,
            useExplicitDates: true,
        });
    }
    const sourceColumnsDefs = availableDefinitions.filter(d => d.valid_time_from === 'source_columns');
    sourceColumnsDefs.forEach(def => {
        options.push({
            id: `source_columns_${def.slug}`,
            label: def.name,
            description: def.note,
            definition: def,
            useExplicitDates: false,
        });
    });
    return options;
  }, [availableDefinitions]);

  const selectedOptionId = React.useMemo(() => {
    if (!selectedDefinition) return null;
    if (selectedDefinition.valid_time_from === 'job_provided') {
      return useExplicitDates ? 'job_provided_explicit_dates' : 'job_provided_time_context';
    }
    if (selectedDefinition.valid_time_from === 'source_columns') {
      return `source_columns_${selectedDefinition.slug}`;
    }
    return null;
  }, [selectedDefinition, useExplicitDates]);

  const handleOptionChange = (id: string) => {
    const option = validityOptions.find(o => o.id === id);
    if (option) {
      setSelectedDefinition(option.definition);
      setUseExplicitDates(option.useExplicitDates);
    }
  };
  
  if (!isClient) {
    return (
      <div className="p-4 border rounded-md bg-gray-50 flex items-center justify-center h-48">
        <Spinner message="Loading validity options..." />
      </div>
    );
  }

  if (!selectedDefinition || validityOptions.length === 0) {
     return (
      <div className="p-4 border rounded-md bg-gray-50 flex items-center justify-center h-48">
        <Spinner message="Loading import definition..." />
      </div>
    );
  }

  return (
    <div className="space-y-4 p-4 border rounded-md bg-gray-50">
      <h3 className="font-medium flex items-center">
        Data Validity Period
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <InfoIcon className="h-4 w-4 ml-2 text-gray-400" />
            </TooltipTrigger>
            <TooltipContent>
              <p className="max-w-xs">
                Choose how to handle the validity period for imported records.
              </p>
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </h3>

      <RadioGroup onValueChange={handleOptionChange} value={selectedOptionId ?? ''} className="space-y-2">
        {validityOptions.map(option => (
          <div key={option.id}>
            <Label 
              htmlFor={option.id} 
              className={cn(
                "flex flex-col p-3 border rounded-md cursor-pointer hover:bg-gray-100",
                selectedOptionId === option.id && "border-blue-500 bg-blue-50"
              )}
            >
              <div className="flex items-center">
                <RadioGroupItem value={option.id} id={option.id} className="mr-3" />
                <span className="font-semibold">{option.label}</span>
              </div>
              {option.description && (
                <p className="text-xs text-gray-600 ml-7 mt-1">{option.description}</p>
              )}
            </Label>
            
            {/* Conditionally render inputs right below the selected option */}
            {selectedOptionId === option.id && (
              <div className="pl-7 mt-2">
                {option.id === 'job_provided_time_context' && (
                  <Select
                    value={selectedContext?.ident ?? ""}
                    onValueChange={handleTimeContextChange}
                  >
                    <SelectTrigger id="time-context" className="w-full">
                      <CalendarIcon className="h-4 w-4 mr-2 text-gray-500" />
                      <SelectValue placeholder="Select a validity period" />
                    </SelectTrigger>
                    <SelectContent>
                      {availableContexts
                        .filter(
                          (tc) =>
                            tc.scope === "input" || tc.scope === "input_and_query",
                        )
                        .map((tc: Tables<'time_context'>) => (
                          <SelectItem key={tc.ident!} value={tc.ident!}>
                            {tc.name_when_input} (
                            {tc.valid_from
                              ? new Date(tc.valid_from).toLocaleDateString()
                              : "N/A"}{" "}
                            -{" "}
                            {tc.valid_to === "infinity"
                              ? "Present"
                              : tc.valid_to
                                ? new Date(tc.valid_to).toLocaleDateString()
                                : "N/A"}
                            )
                          </SelectItem>
                        ))}
                    </SelectContent>
                  </Select>
                )}
                {option.id === 'job_provided_explicit_dates' && (
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <Popover>
                      <PopoverTrigger asChild>
                        <Button
                          variant={"outline"}
                          className={cn(
                            "w-full justify-start text-left font-normal",
                            !explicitStartDate && "text-muted-foreground"
                          )}
                        >
                          <CalendarIcon className="mr-2 h-4 w-4" />
                          {explicitStartDate ? format(new Date(explicitStartDate), "PPP") : <span>Start date</span>}
                        </Button>
                      </PopoverTrigger>
                      <PopoverContent className="w-auto p-0">
                        <Calendar
                          mode="single"
                          selected={explicitStartDate ? new Date(explicitStartDate) : undefined}
                          onSelect={(date) => setExplicitStartDate(date ? format(date, 'yyyy-MM-dd') : null)}
                          initialFocus
                        />
                      </PopoverContent>
                    </Popover>
                    <Popover>
                      <PopoverTrigger asChild>
                        <Button
                          variant={"outline"}
                          className={cn(
                            "w-full justify-start text-left font-normal",
                            !explicitEndDate && "text-muted-foreground"
                          )}
                        >
                          <CalendarIcon className="mr-2 h-4 w-4" />
                          {explicitEndDate ? format(new Date(explicitEndDate), "PPP") : <span>End date</span>}
                        </Button>
                      </PopoverTrigger>
                      <PopoverContent className="w-auto p-0">
                        <Calendar
                          mode="single"
                          selected={explicitEndDate ? new Date(explicitEndDate) : undefined}
                          onSelect={(date) => setExplicitEndDate(date ? format(date, 'yyyy-MM-dd') : null)}
                          initialFocus
                        />
                      </PopoverContent>
                    </Popover>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
      </RadioGroup>
    </div>
  );
}
