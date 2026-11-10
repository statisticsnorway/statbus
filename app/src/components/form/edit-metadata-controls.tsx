"use client";

import { useRef, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useFixedFrameConfirmation } from "@/components/fixed-frame-confirmation";
import { useDetailsPageData, useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { TimeFrameGroupHeading } from "@/components/time-frame-group-heading";
import { groupTimeFrames } from "@/lib/time-frame";
import { format } from "date-fns";
import { CalendarIcon, Pencil } from "lucide-react";
import { useChangeEditFrame } from "./use-start-edit";

interface EditMetadataControlsProps {
  fieldId: string;
}

/**
 * Where an edit applies. The form opens on the Frame the user is looking at:
 * the edit covers the shown value's stretch in that frame (useStartEdit).
 * Choosing another frame re-derives the dates. The pencil opens the details,
 * Data Source, Valid From and Valid To, for a period no frame describes; the
 * Frame link returns to the frame and its dates.
 */
export function EditMetadataControls({ fieldId }: EditMetadataControlsProps) {
  const { dataSources } = useDetailsPageData();
  const {
    currentEdit,
    setEditDataSourceId,
    setEditComment,
    setEditValidFrom,
    setEditValidTo,
  } = useEditManager();
  const { timeFrames } = useTimeFrame();
  const changeEditFrame = useChangeEditFrame();
  const [showDetails, setShowDetails] = useState(false);
  const frameGroups = groupTimeFrames(timeFrames, { forMenu: false });
  const periodText = `${currentEdit.validFrom ?? "?"} to ${currentEdit.validTo ?? "open end"}`;

  // Every save of this edit goes through its form's submit, whichever button
  // starts it. A save reaching into a relative or fixed frame is held and the
  // user is asked (useFixedFrameConfirmation); Confirm submits again, marked
  // confirmed so it passes; Cancel stores nothing.
  const { ask, dialog } = useFixedFrameConfirmation();
  const anchorRef = useRef<HTMLDivElement>(null);
  const confirmedRef = useRef(false);
  useGuardedEffect(
    () => {
      const form = anchorRef.current?.closest("form");
      if (!form) return;
      const onSubmit = (event: SubmitEvent) => {
        if (confirmedRef.current) {
          confirmedRef.current = false;
          return;
        }
        // The period submitted is the form's own valid_from/valid_to fields.
        const data = new FormData(form);
        const held = ask(data.get("valid_from") as string | null, data.get("valid_to") as string | null, () => {
          confirmedRef.current = true;
          form.requestSubmit();
        });
        if (held) {
          event.preventDefault();
          event.stopImmediatePropagation();
        }
      };
      form.addEventListener("submit", onSubmit, { capture: true });
      return () => form.removeEventListener("submit", onSubmit, { capture: true });
    },
    [ask],
    "EditMetadataControls:askBeforeFixedFrameSave"
  );

  return (
    <>
      <input
        type="hidden"
        name="valid_from"
        value={currentEdit.validFrom ?? ""}
      />
      <input type="hidden" name="valid_to" value={currentEdit.validTo ?? ""} />
      {!showDetails && currentEdit.dataSourceId && (
        <input type="hidden" name="data_source_id" value={currentEdit.dataSourceId} />
      )}
      <Separator className="mt-1" />
      <div ref={anchorRef} hidden />
      {dialog}
      {!showDetails ? (
        <div>
          <Label
            htmlFor={`${fieldId}-frame`}
            className="text-xs uppercase text-gray-600"
          >
            Frame
          </Label>
          <div className="flex items-center gap-2">
            <Select
              value={currentEdit.frameIdent ?? undefined}
              onValueChange={(ident) => void changeEditFrame(ident)}
            >
              <SelectTrigger
                id={`${fieldId}-frame`}
                className="w-full border-zinc-300 bg-white"
                data-edit-frame-ident={currentEdit.frameIdent ?? undefined}
              >
                <CalendarIcon className="h-4 w-4 text-gray-500" />
                <SelectValue placeholder="Select a time frame" />
              </SelectTrigger>
              <SelectContent>
                {frameGroups.map((group) => (
                  <SelectGroup key={group.kind}>
                    <SelectLabel>
                      <TimeFrameGroupHeading group={group} />
                    </SelectLabel>
                    {group.frames.map((tf) => (
                      <SelectItem key={tf.ident!} value={tf.ident!}>
                        {tf.name}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                ))}
              </SelectContent>
            </Select>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="h-9"
              aria-label="Edit data source and dates"
              data-edit-details
              onClick={() => setShowDetails(true)}
            >
              <Pencil className="h-4 w-4 text-zinc-700" />
            </Button>
          </div>
          <p className="mt-1 text-xs text-gray-600" data-edit-period>
            Applies from {periodText}
          </p>
        </div>
      ) : (
        <>
          <div className="flex items-center justify-between">
            <span className="text-xs uppercase text-gray-600">Details</span>
            <Button
              type="button"
              variant="link"
              size="sm"
              className="h-6 px-0 text-xs"
              data-edit-back-to-frame
              onClick={() => {
                setShowDetails(false);
                if (currentEdit.frameIdent) void changeEditFrame(currentEdit.frameIdent);
              }}
            >
              Back to frame
            </Button>
          </div>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <Label
                htmlFor={`${fieldId}-datasource`}
                className="text-xs uppercase text-gray-600"
              >
                Data Source
              </Label>
              <Select
                name="data_source_id"
                value={currentEdit.dataSourceId ?? undefined}
                onValueChange={setEditDataSourceId}
              >
                <SelectTrigger
                  id={`${fieldId}-datasource`}
                  className={"w-full border-zinc-300 bg-white"}
                >
                  <SelectValue placeholder="Select data source" />
                </SelectTrigger>
                <SelectContent>
                  {dataSources.map((option) => (
                    <SelectItem key={option.id} value={option.id?.toString() ?? ""}>
                      {option.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label
                htmlFor={`${fieldId}-validfrom`}
                className="text-xs uppercase text-gray-600"
              >
                Valid From
              </Label>
              <div className="relative">
                <Input
                  id={`${fieldId}-validfrom`}
                  type="text"
                  placeholder="yyyy-mm-dd"
                  value={currentEdit.validFrom ?? ""}
                  onChange={(e) => setEditValidFrom(e.target.value)}
                  className="bg-white border-zinc-300"
                />
                <Popover>
                  <PopoverTrigger asChild>
                    <Button
                      variant={"ghost"}
                      className="absolute right-0 top-0 h-full rounded-l-none px-3"
                    >
                      <CalendarIcon className="h-4 w-4" />
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0">
                    <Calendar
                      mode="single"
                      selected={
                        currentEdit.validFrom &&
                        !isNaN(new Date(currentEdit.validFrom).getTime())
                          ? new Date(currentEdit.validFrom)
                          : undefined
                      }
                      onSelect={(date) =>
                        setEditValidFrom(date ? format(date, "yyyy-MM-dd") : "")
                      }
                    />
                  </PopoverContent>
                </Popover>
              </div>
            </div>
            <div>
              <Label
                htmlFor={`${fieldId}-validto`}
                className="text-xs uppercase text-gray-600"
              >
                Valid To (inclusive)
              </Label>
              <div className="relative">
                <Input
                  id={`${fieldId}-validto`}
                  type="text"
                  placeholder="yyyy-mm-dd"
                  value={currentEdit.validTo ?? ""}
                  onChange={(e) => setEditValidTo(e.target.value)}
                  className="bg-white border-zinc-300"
                />
                <Popover>
                  <PopoverTrigger asChild>
                    <Button
                      variant={"ghost"}
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
                        onClick={() => setEditValidTo("infinity")}
                      >
                        Set to Infinity
                      </Button>
                    </div>
                    <Separator />
                    <Calendar
                      mode="single"
                      selected={
                        currentEdit.validTo &&
                        !isNaN(new Date(currentEdit.validTo).getTime())
                          ? new Date(currentEdit.validTo)
                          : undefined
                      }
                      onSelect={(date) =>
                        setEditValidTo(date ? format(date, "yyyy-MM-dd") : "")
                      }
                    />
                  </PopoverContent>
                </Popover>
              </div>
            </div>
          </div>
        </>
      )}
      <div>
        <Label
          htmlFor={`${fieldId}-comment`}
          className="text-xs uppercase text-gray-600"
        >
          Edit Comment
        </Label>
        <Input
          id={`${fieldId}-comment`}
          name="edit_comment"
          type="text"
          className={`bg-white disabled:opacity-80 border-zinc-300`}
          value={currentEdit.editComment ?? ""}
          onChange={(e) => setEditComment(e.target.value)}
          placeholder="Optional comment"
        />
      </div>
    </>
  );
}
