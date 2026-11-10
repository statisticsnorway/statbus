"use client";

import React, { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useImportManager } from "@/atoms/import";
import { Label } from "@/components/ui/label";
import { Tables } from "@/lib/database.types";
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { CalendarIcon, InfoIcon, Pencil } from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { format } from "date-fns";
import { Calendar } from "@/components/ui/calendar";
import { Spinner } from "@/components/ui/spinner";
import { groupTimeFrames, type TimeFrame } from "@/lib/time-frame";
import { TimeFrameGroupHeading } from "@/components/time-frame-group-heading";

/** A frame's period as shown on the import page, e.g. "1/1/2025 - 12/31/2025" or "1/1/2026 - Present". */
function framePeriod(tf: TimeFrame): string {
  const from = tf.valid_from ? new Date(tf.valid_from).toLocaleDateString() : "N/A";
  const to = tf.valid_to === "infinity"
    ? "Present"
    : tf.valid_to ? new Date(tf.valid_to).toLocaleDateString() : "N/A";
  return `${from} - ${to}`;
}

interface ImportTimeFrameSelectorProps {
  unitType: "legal-units" | "establishments" | "establishments-without-legal-unit" | "legal-relationships";
}

/**
 * Chooses how an import job sets validity: a time frame applied to every row,
 * or valid_from/valid_to columns in the file. An import may name any frame, so
 * all frames are listed, grouped by kind (lib/time-frame.ts).
 */
export function ImportTimeFrameSelector({ unitType }: ImportTimeFrameSelectorProps) {
  const { 
    importState: { selectedDefinition, availableDefinitions, useExplicitDates, explicitStartDate, explicitEndDate },
    timeFrame: { availableTimeFrames, selectedTimeFrame },
    setSelectedTimeFrame, 
    setSelectedDefinition,
    setUseExplicitDates,
    setExplicitStartDate,
    setExplicitEndDate
  } = useImportManager();

  const [isClient, setIsClient] = useState(false);
  useGuardedEffect(() => {
    setIsClient(true);
  }, [], 'ImportTimeFrameSelector:setIsClient');

  const timeFrameGroups = groupTimeFrames(availableTimeFrames, { forMenu: false });

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
        id: 'job_provided_time_frame',
        label: 'Apply a time frame to all records',
        description: 'Every imported record is valid for the period of the chosen time frame.',
        definition: jobProvidedDef,
        useExplicitDates: false,
      });
      // options.push({
      //     id: 'job_provided_explicit_dates',
      //     label: 'Provide an explicit start and end date',
      //     description: 'These dates will be used as the default validity for all imported records.',
      //     definition: jobProvidedDef,
      //     useExplicitDates: true,
      // });
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
      return useExplicitDates ? 'job_provided_explicit_dates' : 'job_provided_time_frame';
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
  
  const [showDetails, setShowDetails] = useState(false);
  const jobProvidedOption = validityOptions.find((o) => o.id === 'job_provided_time_frame');
  const chosenOption = validityOptions.find((o) => o.id === selectedOptionId);
  // The frame view applies when the chosen definition takes a frame; any other
  // choice (Source dates, explicit dates) is made and shown in the details.
  const onFrame = selectedOptionId === 'job_provided_time_frame';

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

  if (!showDetails && (onFrame || chosenOption)) {
    return (
      <div className="space-y-2 p-4 border rounded-md bg-gray-50" data-import-validity="frame">
        <Label htmlFor="time-frame" className="text-xs uppercase text-gray-600">
          Frame
        </Label>
        <div className="flex items-center gap-2">
          {onFrame ? (
            <Select
              value={selectedTimeFrame?.ident ?? ""}
              onValueChange={setSelectedTimeFrame}
            >
              <SelectTrigger id="time-frame" className="w-full bg-white" data-import-frame-ident={selectedTimeFrame?.ident ?? undefined}>
                <CalendarIcon className="h-4 w-4 mr-2 text-gray-500" />
                <SelectValue placeholder="Select a time frame" />
              </SelectTrigger>
              <SelectContent>
                {timeFrameGroups.map((group) => (
                  <SelectGroup key={group.kind}>
                    <SelectLabel><TimeFrameGroupHeading group={group} /></SelectLabel>
                    {group.frames.map((tf) => (
                      <SelectItem key={tf.ident!} value={tf.ident!}>
                        {tf.name} ({framePeriod(tf)})
                      </SelectItem>
                    ))}
                  </SelectGroup>
                ))}
              </SelectContent>
            </Select>
          ) : (
            <div className="flex w-full items-center justify-between rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm" data-import-validity-option={chosenOption?.id}>
              <span>{chosenOption?.label}: dates from the file</span>
              {jobProvidedOption && (
                <Button type="button" variant="link" size="sm" className="h-6 px-0" onClick={() => handleOptionChange(jobProvidedOption.id)}>
                  Use a frame
                </Button>
              )}
            </div>
          )}
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-9"
            aria-label="Other validity options, including source dates"
            data-import-validity-details
            onClick={() => setShowDetails(true)}
          >
            <Pencil className="h-4 w-4 text-zinc-700" />
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4 p-4 border rounded-md bg-gray-50" data-import-validity="details">
      <h3 className="font-medium flex items-center justify-between">
        <span className="flex items-center">
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
        </span>
        {(onFrame || chosenOption) && (
          <Button type="button" variant="link" size="sm" className="h-6 px-0 text-xs" data-import-validity-back onClick={() => setShowDetails(false)}>
            Done
          </Button>
        )}
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
                {option.id === 'job_provided_time_frame' && (
                  <Select
                    value={selectedTimeFrame?.ident ?? ""}
                    onValueChange={setSelectedTimeFrame}
                  >
                    <SelectTrigger id="time-frame" className="w-full">
                      <CalendarIcon className="h-4 w-4 mr-2 text-gray-500" />
                      <SelectValue placeholder="Select a time frame" />
                    </SelectTrigger>
                    <SelectContent>
                      {timeFrameGroups.map((group) => (
                        <SelectGroup key={group.kind}>
                          <SelectLabel><TimeFrameGroupHeading group={group} /></SelectLabel>
                          {group.frames.map((tf) => (
                            <SelectItem key={tf.ident!} value={tf.ident!}>
                              {tf.name} ({framePeriod(tf)})
                            </SelectItem>
                          ))}
                        </SelectGroup>
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
