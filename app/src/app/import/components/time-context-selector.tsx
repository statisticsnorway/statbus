"use client";

import React, { useEffect, useState } from "react";
import { useImportManager, ImportMode } from "@/atoms/import"; // Updated import
import { Label } from "@/components/ui/label";
import { Tables } from "@/lib/database.types";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { CalendarIcon, InfoIcon } from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

interface TimeContextSelectorProps {
  unitType: "legal-units" | "establishments" | "establishments-without-legal-unit";
}

export function TimeContextSelector({ unitType }: TimeContextSelectorProps) {
  const getModeFromUnitType = (): ImportMode => {
    switch(unitType) {
      case 'legal-units': return 'legal_unit';
      case 'establishments': return 'establishment_formal';
      case 'establishments-without-legal-unit': return 'establishment_informal';
      default: throw new Error(`Invalid unitType: ${unitType}`);
    }
  }

  const { 
    timeContext: { availableContexts, selectedContext, useExplicitDates },
    setSelectedTimeContext, 
    setUseExplicitDates
  } = useImportManager(getModeFromUnitType()); // Updated hook call

  const [isClient, setIsClient] = useState(false);
  useEffect(() => {
    setIsClient(true);
  }, []);

  // Pass the ident string directly to the context setter
  const handleTimeContextChange = (value: string) => {
    // Find the full object if needed locally, but pass ident to setter
    // const selectedObject = timeContexts.find(tc => tc.ident === value);
    setSelectedTimeContext(value); // Pass ident
  };

  const getUnitTypeLabel = () => {
    switch (unitType) {
      case "legal-units":
        return "Legal Units";
      case "establishments":
        return "Establishments";
      case "establishments-without-legal-unit":
        return "Establishments Without Legal Unit";
      default:
        return "Units";
    }
  };

  if (!isClient || availableContexts.length === 0) {
    return <div>Loading validity periods...</div>;
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
                Choose how to handle dates for your imported data. You can either apply a predefined validity period to all records, or provide explicit dates in your CSV file.
              </p>
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </h3>
      
      <RadioGroup 
        defaultValue="time-context" 
        value={useExplicitDates ? "explicit-dates" : "time-context"}
        onValueChange={(value) => setUseExplicitDates(value === "explicit-dates")}
        className="space-y-4"
      >
        <div className="flex items-start space-x-2">
          <RadioGroupItem value="time-context" id="time-context-option" className="mt-1" />
          <div className="grid gap-1.5">
            <Label htmlFor="time-context-option" className="font-medium">
              Apply a validity period to all records
            </Label>
            
            {!useExplicitDates && (
              <div className="mt-2">
                <Select
                  // Use ident for value, provide empty string if null
                  value={selectedContext?.ident ?? ""}
                  onValueChange={handleTimeContextChange}
                >
                  <SelectTrigger id="time-context" className="w-full">
                    <CalendarIcon className="h-4 w-4 mr-2 text-gray-500" />
                    <SelectValue placeholder="Select a validity period" />
                  </SelectTrigger>
                  <SelectContent>
                    {availableContexts.map((tc: Tables<'time_context'>) => (
                      // Use ident for key and value, handle potential null ident
                      <SelectItem key={tc.ident ?? `null-ident-${Math.random()}`} value={tc.ident ?? ""}>
                        {/* Use name_when_input, handle null dates */}
                        {tc.name_when_input} ({tc.valid_from ? new Date(tc.valid_from).toLocaleDateString() : 'N/A'} - {
                          tc.valid_to === 'infinity' ? 'Present' : tc.valid_to ? new Date(tc.valid_to).toLocaleDateString() : 'N/A'
                        })
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                
                {selectedContext && (
                  <div className="text-xs text-gray-600 mt-2 pl-1">
                    All records will use the time period:
                    <div className="font-medium mt-1">
                      {/* Handle null dates */}
                      {selectedContext.valid_from ? new Date(selectedContext.valid_from).toLocaleDateString() : 'N/A'} to {
                        selectedContext.valid_to === 'infinity' ? 'Present' : selectedContext.valid_to ? new Date(selectedContext.valid_to).toLocaleDateString() : 'N/A'
                      }
                    </div>
                  </div>
                )}
              </div>
            )}
            
            {useExplicitDates && (
              <p className="text-sm text-gray-500 mt-1">
                A predefined validity period will be applied to all records.
              </p>
            )}
          </div>
        </div>
        
        <div className="flex items-start space-x-2">
          <RadioGroupItem value="explicit-dates" id="explicit-dates-option" className="mt-1" />
          <div className="grid gap-1.5">
            <Label htmlFor="explicit-dates-option" className="font-medium">
              Use explicit valid_from and valid_to columns
            </Label>
            <p className="text-sm text-gray-500">
              Your CSV must include valid_from and valid_to date columns in ISO format (YYYY-MM-DD)
            </p>
          </div>
        </div>
      </RadioGroup>
    </div>
  );
}
