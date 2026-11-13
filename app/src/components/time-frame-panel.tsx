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
import { TimeFrameGroupHeading } from "@/components/time-frame-group-heading";
import { groupTimeFrames, type TimeFrame } from "@/lib/time-frame";
import { cn } from "@/lib/utils";
import { format } from "date-fns";
import { CalendarIcon } from "lucide-react";

/** How a change is dated: by a time frame, by chosen dates, or (imports only) by the file's own columns. */
export type ValidityChoice = "frame" | "dates" | "source_dates";

/**
 * The panel's views, offered by the caller in this order. Simple and Advanced
 * always; Timeline when the caller passes the field's timeline (an edit), where
 * the user ticks the stretch of the field's history the change applies to.
 */
export type TimeFramePanelMode = "simple" | "advanced" | "timeline";
export const TIME_FRAME_PANEL_MODES: { mode: TimeFramePanelMode; label: string; hint: string }[] = [
  { mode: "simple", label: "Simple", hint: "Choose a time frame" },
  { mode: "advanced", label: "Advanced", hint: "Choose a frame, dates or source dates" },
  { mode: "timeline", label: "Timeline", hint: "Tick the periods of this field's history to change" },
];

/** A frame's period, ISO dates, e.g. "2025-01-01 – 2025-12-31" or "2026-01-01 – Present". */
export function framePeriod(tf: Pick<TimeFrame, "valid_from" | "valid_to">): string {
  const to = tf.valid_to === "infinity" ? "Present" : tf.valid_to ?? "?";
  return `${tf.valid_from ?? "?"} – ${to}`;
}

const headingClass = "text-xs font-medium text-zinc-500";

/**
 * Why a date typed into Advanced's From or To cannot be used: it falls outside
 * the bounds (where the unit exists, for an edit of a unit's record). Null for a
 * date inside them, an open end, a date not yet fully typed, or no bounds.
 */
export function dateOutsideBounds(value: string | null, bounds: DateBounds | undefined): string | null {
  if (!bounds || !value || value === "infinity" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  if (value < bounds.from) return `The unit exists from ${bounds.from}`;
  if (bounds.to !== "infinity" && value > bounds.to) return `The unit exists until ${bounds.to}`;
  return null;
}

function DateInput({
  id,
  label,
  value,
  onChange,
  allowInfinity,
  bounds,
}: {
  id: string;
  label: string;
  value: string | null;
  onChange: (date: string | null) => void;
  allowInfinity?: boolean;
  bounds?: DateBounds;
}) {
  const parsed = value && value !== "infinity" && !isNaN(new Date(value).getTime()) ? new Date(value) : undefined;
  const earliest = bounds?.from ? new Date(`${bounds.from}T00:00:00`) : undefined;
  const latest = bounds?.to && bounds.to !== "infinity" ? new Date(`${bounds.to}T00:00:00`) : undefined;
  const problem = dateOutsideBounds(value, bounds);
  // The calendar's month and year are drop-downs, from the unit's first year
  // (or 1900) to its last (or ten years ahead), so a far date is two picks away.
  const thisYear = new Date().getFullYear();
  const startMonth = earliest ?? new Date(1900, 0, 1);
  const endMonth = latest ?? new Date(thisYear + 10, 11, 31);
  return (
    <div className="relative min-w-0 flex-1">
      <Input
        id={id}
        aria-label={label}
        aria-invalid={problem ? true : undefined}
        type="text"
        placeholder={`${label} yyyy-mm-dd`}
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value || null)}
        className={cn("h-9 border-zinc-300 bg-white pr-9", problem && "border-red-500 focus-visible:ring-red-500/40")}
      />
      {problem && (
        <p className="mt-1 text-xs text-red-600" data-date-out-of-bounds="">
          {problem}
        </p>
      )}
      <Popover>
        <PopoverTrigger asChild>
          <Button type="button" variant="ghost" className="absolute right-0 top-0 h-9 rounded-l-none px-2" aria-label={`Pick ${label}`}>
            <CalendarIcon className="h-4 w-4" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-auto p-0">
          {allowInfinity && !latest && (
            <div className="border-b p-2">
              <Button type="button" variant="outline" className="w-full" onClick={() => onChange("infinity")}>
                No end (until further notice)
              </Button>
            </div>
          )}
          <Calendar
            mode="single"
            captionLayout="dropdown"
            startMonth={startMonth}
            endMonth={endMonth}
            selected={parsed}
            defaultMonth={parsed && (!earliest || parsed >= earliest) ? parsed : earliest}
            disabled={[...(earliest ? [{ before: earliest }] : []), ...(latest ? [{ after: latest }] : [])]}
            onSelect={(d) => onChange(d ? format(d, "yyyy-MM-dd") : null)}
          />
          {bounds?.from && (
            <p className="border-t px-3 py-2 text-xs text-zinc-500" data-date-bounds="">
              The unit exists {bounds.from} – {latest ? bounds.to : "Present"}
            </p>
          )}
        </PopoverContent>
      </Popover>
    </div>
  );
}

export interface TimeFramePanelProps {
  /** Prefix for element ids, unique on the page. */
  idPrefix: string;
  timeFrames: readonly TimeFrame[];
  mode: TimeFramePanelMode;
  onModeChange: (mode: TimeFramePanelMode) => void;
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
  /** Shown for no source, and offered in the list to clear it: e.g. the import definition's own source. Default "None". */
  dataSourcePlaceholder?: string;
  comment: string | null;
  onCommentChange: (comment: string | null) => void;
  /** Rendered as hidden fields for a form post (the edit form): valid_from, valid_to, data_source_id, edit_comment. */
  formFields?: boolean;
  /** The Timeline view's body (an edit's field timeline). Absent, the view is not offered. */
  timeline?: React.ReactNode;
  /**
   * Shown on the Timeline view's own line, right-aligned: the edit's
   * Change | Remove switch and Tick all (STATBUS-611). Absent, no such line.
   */
  timelineControls?: React.ReactNode;
  /**
   * Hides Data source and Comment: a removal (Remove mode) stores no values, so
   * it has none to describe (owner 2026-11-13: removal carries only the period).
   */
  hideMetadata?: boolean;
  /**
   * The dates a change can have (an edit of a record: where its unit exists).
   * Advanced's date pickers offer only dates inside them. Absent, any date.
   */
  dateBounds?: DateBounds;
}

/** The first and last day a change can cover; to "infinity" for no end. */
export interface DateBounds {
  from: string;
  to: string;
}

/** The Data source list's entry for no source: Radix Select reserves the empty value. */
const NO_SOURCE = "__none__";

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
    timeline,
    timelineControls,
    hideMetadata,
    dateBounds,
  } = props;
  const groups = groupTimeFrames(timeFrames, { forMenu: false });
  const advanced = mode === "advanced";
  const modes = TIME_FRAME_PANEL_MODES.filter((m) => m.mode !== "timeline" || timeline);
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
          <div
            role="radiogroup"
            aria-label="Time frame view"
            className="inline-flex rounded-md border border-zinc-200 bg-zinc-100 p-0.5 text-xs"
            data-time-frame-mode-switch
          >
            {modes.map((m) => (
              <button
                key={m.mode}
                type="button"
                role="radio"
                aria-checked={mode === m.mode}
                title={m.hint}
                data-time-frame-mode={m.mode}
                onClick={() => mode !== m.mode && onModeChange(m.mode)}
                className={cn(
                  "rounded px-2 py-0.5 text-zinc-600 transition-colors",
                  mode === m.mode ? "bg-white font-medium text-zinc-900 shadow-sm" : "hover:text-zinc-900"
                )}
              >
                {m.label}
              </button>
            ))}
          </div>
        </div>

        {mode === "timeline" && timeline ? (
          <div className="space-y-1">
            {timelineControls && (
              <div className="flex items-center justify-end gap-3" data-timeline-controls="">
                {timelineControls}
              </div>
            )}
            {timeline}
          </div>
        ) : !advanced ? (
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
                <DateInput id={`${idPrefix}-valid-from`} label="From" value={validFrom} onChange={onValidFromChange} bounds={dateBounds} />
                <DateInput id={`${idPrefix}-valid-to`} label="To" value={validTo} onChange={onValidToChange} allowInfinity bounds={dateBounds} />
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

      {!hideMetadata && (
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-[minmax(0,18rem)_1fr]">
        <div className="space-y-1.5">
          <Label htmlFor={`${idPrefix}-datasource`} className={headingClass}>
            Data source
          </Label>
          <Select
            value={dataSourceCode ?? NO_SOURCE}
            onValueChange={(code) => onDataSourceChange(code === NO_SOURCE ? null : code)}
          >
            <SelectTrigger id={`${idPrefix}-datasource`} className="h-9 w-full min-w-0 border-zinc-300 bg-white">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {/* Choosing no source clears it; on an import the file or the definition then decides. */}
              <SelectItem value={NO_SOURCE}>
                <span className="text-zinc-500">{dataSourcePlaceholder ?? "None"}</span>
              </SelectItem>
              {dataSources.map((d) => (
                <SelectItem key={d.code!} value={d.code!}>
                  <span className="font-mono text-xs text-zinc-500">{d.code}</span>
                  <span className="text-zinc-400"> – </span>
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
          {/* One line at rest; focused, it opens to three lines and grows with what is typed. */}
          <textarea
            id={`${idPrefix}-comment`}
            rows={1}
            className={cn(
              "block w-full resize-none rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm leading-6 shadow-xs outline-none",
              "placeholder:text-zinc-500 focus-visible:border-zinc-950 focus-visible:ring-[3px] focus-visible:ring-zinc-950/50",
              "max-h-9 overflow-hidden text-ellipsis [field-sizing:content]",
              "focus:max-h-60 focus:min-h-20 focus:overflow-auto"
            )}
            value={comment ?? ""}
            onChange={(e) => onCommentChange(e.target.value || null)}
            placeholder="Optional, stored with every change"
          />
        </div>
      </div>
      )}
    </div>
  );
}
