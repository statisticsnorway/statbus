"use client";

import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Separator } from "@/components/ui/separator";
import { useTimeContext } from "@/atoms/app-derived";
import { type StatisticalUnit } from "@/atoms/search";
import { format } from "date-fns";
import { CalendarIcon } from "lucide-react";
import { useEffect, useState } from "react";

interface CombineUnitsDialogProps {
  readonly isOpen: boolean;
  readonly onOpenChange: (isOpen: boolean) => void;
  readonly legalUnit: StatisticalUnit;
  readonly enterprise: StatisticalUnit;
  readonly onConfirm: (validFrom: string, validTo: string) => Promise<void>;
}

export function CombineUnitsDialog({
  isOpen,
  onOpenChange,
  legalUnit,
  enterprise,
  onConfirm,
}: CombineUnitsDialogProps) {
  const { selectedTimeContext } = useTimeContext();
  const [validFrom, setValidFrom] = useState<string>("");
  const [validTo, setValidTo] = useState<string>("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Initialize defaults from selected time context when dialog opens
  useEffect(() => {
    if (isOpen && selectedTimeContext) {
      setValidFrom(selectedTimeContext.valid_from ?? "");
      // valid_to from context might be "infinity" or a date - both are valid
      setValidTo(selectedTimeContext.valid_to ?? "");
    }
  }, [isOpen, selectedTimeContext]);

  const handleConfirm = async () => {
    setIsSubmitting(true);
    try {
      await onConfirm(validFrom, validTo);
    } finally {
      setIsSubmitting(false);
    }
  };

  // Display value for valid_to - show blank for infinity (matching existing pattern)
  const validToDisplay = validTo === "infinity" ? "" : validTo;

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Combine Units</DialogTitle>
          <DialogDescription>
            This will connect{" "}
            <span className="font-medium">{legalUnit.name}</span> (Legal Unit)
            to <span className="font-medium">{enterprise.name}</span>{" "}
            (Enterprise).
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label
                htmlFor="combine-valid-from"
                className="text-xs uppercase text-gray-600"
              >
                Valid From
              </Label>
              <div className="relative">
                <Input
                  id="combine-valid-from"
                  type="text"
                  placeholder="yyyy-mm-dd"
                  value={validFrom}
                  onChange={(e) => setValidFrom(e.target.value)}
                  className="bg-white border-zinc-300"
                />
                <Popover>
                  <PopoverTrigger asChild>
                    <Button
                      variant="ghost"
                      className="absolute right-0 top-0 h-full rounded-l-none px-3"
                    >
                      <CalendarIcon className="h-4 w-4" />
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0">
                    <Calendar
                      mode="single"
                      selected={
                        validFrom && !isNaN(new Date(validFrom).getTime())
                          ? new Date(validFrom)
                          : undefined
                      }
                      onSelect={(date) =>
                        setValidFrom(date ? format(date, "yyyy-MM-dd") : "")
                      }
                    />
                  </PopoverContent>
                </Popover>
              </div>
            </div>

            <div>
              <Label
                htmlFor="combine-valid-to"
                className="text-xs uppercase text-gray-600"
              >
                Valid To
              </Label>
              <div className="relative">
                <Input
                  id="combine-valid-to"
                  type="text"
                  placeholder="yyyy-mm-dd"
                  value={validToDisplay}
                  onChange={(e) => setValidTo(e.target.value || "infinity")}
                  className="bg-white border-zinc-300"
                />
                <Popover>
                  <PopoverTrigger asChild>
                    <Button
                      variant="ghost"
                      className="absolute right-0 top-0 h-full rounded-l-none px-3"
                    >
                      <CalendarIcon className="h-4 w-4" />
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0">
                    <div className="p-2">
                      <Button
                        variant="outline"
                        className="w-full"
                        onClick={() => setValidTo("infinity")}
                      >
                        Set to Infinity
                      </Button>
                    </div>
                    <Separator />
                    <Calendar
                      mode="single"
                      selected={
                        validTo &&
                        validTo !== "infinity" &&
                        !isNaN(new Date(validTo).getTime())
                          ? new Date(validTo)
                          : undefined
                      }
                      onSelect={(date) =>
                        setValidTo(date ? format(date, "yyyy-MM-dd") : "infinity")
                      }
                    />
                  </PopoverContent>
                </Popover>
              </div>
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={isSubmitting}
          >
            Cancel
          </Button>
          <Button onClick={handleConfirm} disabled={isSubmitting}>
            {isSubmitting ? "Combining..." : "Confirm Combination"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
