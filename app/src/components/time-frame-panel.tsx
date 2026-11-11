"use client";

import { Calendar } from "@/components/ui/calendar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { TimeFrameGroupHeading } from "@/components/time-frame-group-heading";
import { groupTimeFrames, type TimeFrame } from "@/lib/time-frame";
import { cn } from "@/lib/utils";
import { format } from "date-fns";
import { CalendarIcon } from "lucide-react";

/** How a change is dated: by a time frame, by chosen dates, or (imports only) by the file's own columns. */
export type ValidityChoice = "frame" | "dates" | "source_dates";

/** A frame's period, ISO dates, e.g. "2025-01-01 – 2025-12-31" or "2026-01-01 – Present". */
export function framePeriod(tf: Pick<TimeFrame, "valid_from" | "valid_to">): string {
  const to = tf.valid_to === "infinity" ? "Present" : tf.valid_to ?? "?";
  return `${tf.valid_from ?? "?"} – ${to}`;
}

const headingClass = "text-xs font-medium text-zinc-500";

function DateInput({
  id,
  label,
  value,
  onChange,
  allowInfinity,
}: {
  id: string;
  label: string;
  value: string | null;
  onChange: (date: string | null) => void;
  allowInfinity?: boolean;
}) {
  const parsed = value && value !== "infinity" && !isNaN(new Date(value).getTime()) ? new Date(value) : undefined;
  return (
    <div className="relative min-w-0 flex-1">
      <Input
        id={id}
        aria-label={label}
        type="text"
        placeholder={`${label} yyyy-mm-dd`}
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value || null)}
        className="h-9 border-zinc-300 bg-white pr-9"
      />
      <Popover>
        <PopoverTrigger asChild>
          <Button type="button" variant="ghost" className="absolute right-0 top-0 h-full rounded-l-none px-2" aria-label={`Pick ${label}`}>
            <CalendarIcon className="h-4 w-4" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-auto p-0">
          {allowInfinity && (
            <div className="border-b p-2">
              <Button type="button" variant="outline" className="w-full" onClick={() => onChange("infinity")}>
                No end (until further notice)
              </Button>
            </div>
          )}
          <Calendar mode="single" selected={parsed} onSelect={(d) => onChange(d ? format(d, "yyyy-MM-dd") : null)} />
        </PopoverContent>
      </Popover>
    </div>
  );
}

export interface TimeFramePanelProps {
  /** Prefix for element ids, unique on the page. */
  idPrefix: string;
  timeFrames: readonly TimeFrame[];
  mode: "simple" | "advanced";
  onModeChange: (mode: "simple" | "advanced") => void;
  choice: ValidityChoice;
  onChoiceChange: (choice: ValidityChoice) => void;
  frameIdent: string | null;
  onFrameChange: (ident: string) => void;
  validFrom: string | null;
  validTo: string | null;
  onValidFromChange: (date: string | null) => void;
  onValidToChange: (date: string | null) => void;
  /** Imports only: the file carries valid_from and valid_to. Absent, the choice is not offered. */
  sourceDates?: { label: string; description: string };
  dataSources: readonly { id: number | null; code: string | null; name: string | null }[];
  /** The chosen data source, by code. */
  dataSourceCode: string | null;
  onDataSourceChange: (code: string | null) => void;
  /** Shown when no source is chosen, e.g. the import definition's own source. */
  dataSourcePlaceholder?: string;
  comment: string | null;
  onCommentChange: (comment: string | null) => void;
  /** Rendered as hidden fields for a form post (the edit form): valid_from, valid_to, data_source_id, edit_comment. */
  formFields?: boolean;
}

/**
 * Where a change applies and where it comes from, the same for an edit and
 * an import. Simple: one Time frame. Advanced: Frame, Dates, or Source dates
 * (imports), in one radio group with each choice's inputs on its own row.
 * Below, Data source and Comment. The switch beside the heading moves between
 * the two; Simple always means a frame.
 */
export function TimeFramePanel(props: TimeFramePanelProps) {
  const {
    idPrefix,
    timeFrames,
    mode,
    onModeChange,
    choice,
    onChoiceChange,
    frameIdent,
    onFrameChange,
    validFrom,
    validTo,
    onValidFromChange,
    onValidToChange,
    sourceDates,
    dataSources,
    dataSourceCode,
    onDataSourceChange,
    dataSourcePlaceholder,
    comment,
    onCommentChange,
    formFields,
  } = props;
  const groups = groupTimeFrames(timeFrames, { forMenu: false });
  const advanced = mode === "advanced";
  const chosenSource = dataSources.find((d) => d.code === dataSourceCode);

  const frameSelect = (
    <Select value={frameIdent ?? ""} onValueChange={onFrameChange} disabled={advanced && choice !== "frame"}>
      <SelectTrigger
        id={`${idPrefix}-frame`}
        className="h-9 w-full min-w-0 justify-between border-zinc-300 bg-white"
        data-frame-ident={frameIdent ?? undefined}
      >
        <span className="flex min-w-0 items-center gap-2">
          <CalendarIcon className="h-4 w-4 shrink-0 text-zinc-500" />
          <SelectValue placeholder="Select a time frame" />
        </span>
      </SelectTrigger>
      <SelectContent>
        {groups.map((group) => (
          <SelectGroup key={group.kind}>
            <SelectLabel>
              <TimeFrameGroupHeading group={group} />
            </SelectLabel>
            {group.frames.map((tf) => (
              <SelectItem key={tf.ident!} value={tf.ident!}>
                {tf.name} <span className="text-zinc-500">({framePeriod(tf)})</span>
              </SelectItem>
            ))}
          </SelectGroup>
        ))}
      </SelectContent>
    </Select>
  );

  return (
    <div className="space-y-3 rounded-md border border-zinc-200 bg-white p-3" data-time-frame-panel={mode}>
      {formFields && (
        <>
          <input type="hidden" name="valid_from" value={validFrom ?? ""} />
          <input type="hidden" name="valid_to" value={validTo === "infinity" ? "" : validTo ?? ""} />
          <input type="hidden" name="data_source_id" value={chosenSource?.id?.toString() ?? ""} />
          <input type="hidden" name="edit_comment" value={comment ?? ""} />
        </>
      )}
      <div className="space-y-1.5">
        <div className="flex items-center justify-between">
          <Label htmlFor={`${idPrefix}-frame`} className={headingClass}>
            Time frame
          </Label>
          <label className="flex cursor-pointer items-center gap-2 text-xs text-zinc-500">
            <span className={cn(!advanced && "font-medium text-zinc-900")}>Simple</span>
            <Switch
              checked={advanced}
              onCheckedChange={(on) => onModeChange(on ? "advanced" : "simple")}
              aria-label="Advanced: choose dates or source dates"
              data-time-frame-mode-switch
            />
            <span className={cn(advanced && "font-medium text-zinc-900")}>Advanced</span>
          </label>
        </div>

        {!advanced ? (
          frameSelect
        ) : (
          <RadioGroup
            value={choice}
            onValueChange={(v) => onChoiceChange(v as ValidityChoice)}
            className="gap-1.5"
          >
            <div className="grid grid-cols-[7.5rem_1fr] items-center gap-2" data-validity-choice="frame">
              <label className="flex cursor-pointer items-center gap-2 text-sm">
                <RadioGroupItem value="frame" id={`${idPrefix}-choice-frame`} />
                Frame
              </label>
              {frameSelect}
            </div>
            <div className="grid grid-cols-[7.5rem_1fr] items-center gap-2" data-validity-choice="dates">
              <label className="flex cursor-pointer items-center gap-2 text-sm">
                <RadioGroupItem value="dates" id={`${idPrefix}-choice-dates`} />
                Dates
              </label>
              <div className={cn("flex gap-2", choice !== "dates" && "pointer-events-none opacity-50")}>
                <DateInput id={`${idPrefix}-valid-from`} label="From" value={validFrom} onChange={onValidFromChange} />
                <DateInput id={`${idPrefix}-valid-to`} label="To" value={validTo} onChange={onValidToChange} allowInfinity />
              </div>
            </div>
            {sourceDates && (
              <div className="grid grid-cols-[7.5rem_1fr] items-center gap-2" data-validity-choice="source_dates">
                <label className="flex cursor-pointer items-center gap-2 text-sm">
                  <RadioGroupItem value="source_dates" id={`${idPrefix}-choice-source-dates`} />
                  Source dates
                </label>
                <p className={cn("text-xs text-zinc-600", choice !== "source_dates" && "opacity-50")}>
                  {sourceDates.description}
                </p>
              </div>
            )}
          </RadioGroup>
        )}
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-[minmax(0,14rem)_1fr]">
        <div className="space-y-1.5">
          <Label htmlFor={`${idPrefix}-datasource`} className={headingClass}>
            Data source
          </Label>
          <Select
            value={dataSourceCode ?? ""}
            onValueChange={(code) => onDataSourceChange(code || null)}
          >
            <SelectTrigger id={`${idPrefix}-datasource`} className="h-9 w-full border-zinc-300 bg-white">
              <SelectValue placeholder={dataSourcePlaceholder ?? "Select data source"} />
            </SelectTrigger>
            <SelectContent>
              {dataSources.map((d) => (
                <SelectItem key={d.code!} value={d.code!}>
                  {d.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor={`${idPrefix}-comment`} className={headingClass}>
            Comment
          </Label>
          <Input
            id={`${idPrefix}-comment`}
            type="text"
            className="h-9 border-zinc-300 bg-white"
            value={comment ?? ""}
            onChange={(e) => onCommentChange(e.target.value || null)}
            placeholder="Optional, stored with every change"
          />
        </div>
      </div>
    </div>
  );
}
