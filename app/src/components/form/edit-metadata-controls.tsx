"use client";

import { useRef, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useFixedFrameConfirmation } from "@/components/fixed-frame-confirmation";
import {
  TimeFramePanel,
  dateOutsideBounds,
  type TimeFramePanelMode,
  type ValidityChoice,
} from "@/components/time-frame-panel";
import { useDetailsPageData, useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { Separator } from "@/components/ui/separator";
import { useChangeEditFrame } from "./use-start-edit";
import { FieldTimeline, useFieldTimeline } from "./field-timeline-view";
import { opensInTimeline, periodsInRange, selectionRange, toggleSelection } from "./field-timeline";
import { TimelineSkeleton, useUnitExistence } from "./timeline-skeleton-view";
import { skeletonPieces, skeletonSelectionRange } from "./timeline-skeleton";
import { capToExistence } from "./unit-existence";
import { isRemovable, RemovalTimeline, TickAllPieces } from "./remove-record-button";
import { cn } from "@/lib/utils";

interface EditMetadataControlsProps {
  fieldId: string;
}

/**
 * Where an edit applies and where it comes from: the Time frame panel, the
 * same as on the import pages (components/time-frame-panel.tsx). The edit
 * opens on the frame the user is looking at and covers the shown value's
 * stretch in it (useStartEdit). Advanced offers chosen Dates instead. Timeline
 * shows the field's history and the edit applies to the ticked stretch of it;
 * Edit opens there when the shown value is not the field's newest. Data
 * source and Comment are stored with the change. A save that reaches into a
 * relative or fixed frame asks first.
 */
export function EditMetadataControls({ fieldId }: EditMetadataControlsProps) {
  const { dataSources } = useDetailsPageData();
  const {
    currentEdit,
    setEditDataSourceId,
    setEditComment,
    setEditValidFrom,
    setEditValidTo,
    setEditRemoving,
  } = useEditManager();
  const { timeFrames } = useTimeFrame();
  const changeEditFrame = useChangeEditFrame();
  const [mode, setMode] = useState<TimeFramePanelMode>("simple");
  const [choice, setChoice] = useState<ValidityChoice>("frame");

  // The field's timeline, when the field names its rows. The edit's dates are
  // the ticked stretch; the ticks are read back from the dates, so the frame
  // and Advanced views and the Timeline view always agree.
  const { periods, loaded } = useFieldTimeline(currentEdit.source);
  const selected = periodsInRange(periods, currentEdit.validFrom, currentEdit.validTo);
  const handleToggle = (index: number) => {
    const range = selectionRange(periods, toggleSelection(selected, index));
    setEditValidFrom(range?.validFrom ?? null);
    setEditValidTo(range && range.validTo !== "infinity" ? range.validTo : null);
  };

  // A record the unit does not have yet (no rows): its Timeline view is a
  // skeleton of the frames, cut to where the unit exists (the cap). The edit's
  // dates are the picked pieces; it starts on the Live piece, which starts
  // where the unit does when the unit was born inside Live (STATBUS-609).
  const existence = useUnitExistence(currentEdit.source);
  const empty = loaded && periods.length === 0;
  const pieces = empty && existence ? skeletonPieces(timeFrames, existence) : [];
  const picked = pieces.flatMap((p, i) =>
    p.available &&
    currentEdit.validFrom &&
    p.valid_from <= (currentEdit.validTo ?? "9999-12-31") &&
    (p.valid_to === "infinity" || p.valid_to >= currentEdit.validFrom)
      ? [i]
      : []
  );
  const handlePick = (index: number) => {
    const range = skeletonSelectionRange(pieces, toggleSelection(picked, index));
    setEditValidFrom(range?.validFrom ?? null);
    setEditValidTo(range && range.validTo !== "infinity" ? range.validTo : null);
  };

  // Edit opens in the Timeline view when the edit's frame holds more than one
  // value of the field (opensInTimeline); one value covering the frame opens
  // Simple. Decided once per edit, when its dates and rows are known.
  const openedRef = useRef(false);
  const datesKnown = !!currentEdit.validFrom;
  useGuardedEffect(
    () => {
      if (openedRef.current || !loaded || !datesKnown) return;
      openedRef.current = true;
      const frame = timeFrames.find((tf) => tf.ident === currentEdit.frameIdent);
      if (opensInTimeline(periods, frame)) setMode("timeline");
    },
    [loaded, datesKnown],
    "EditMetadataControls:openInTimeline"
  );

  // A first value starts no earlier than the unit: the edit's opening dates
  // (the frame's) are capped to the unit's existence once it is read.
  const cappedRef = useRef(false);
  useGuardedEffect(
    () => {
      if (cappedRef.current || !empty || !existence || !currentEdit.validFrom) return;
      cappedRef.current = true;
      const capped = capToExistence(existence, currentEdit.validFrom, currentEdit.validTo ?? null);
      if (capped && capped.validFrom !== currentEdit.validFrom) setEditValidFrom(capped.validFrom);
    },
    [empty, existence, datesKnown],
    "EditMetadataControls:capFirstValueToUnit"
  );

  // Simple always means a frame: the frame's dates come back.
  // Leaving the Timeline view leaves Remove mode: the other views change values.
  const handleModeChange = (next: TimeFramePanelMode) => {
    setMode(next);
    if (next !== "timeline" && currentEdit.removing) setEditRemoving(null);
    if (next === "simple") handleChoiceChange("frame");
  };
  const removing = currentEdit.removing != null;
  const canRemove = isRemovable(currentEdit.source) && loaded && periods.length > 0;
  // Change | Remove, on the Timeline view's own line (owner 2026-11-13): Remove
  // turns the timeline into pieces per frame to tick for removal.
  const changeRemoveSwitch = canRemove ? (
    <>
      {removing && <TickAllPieces />}
      <div
        role="radiogroup"
        aria-label="Change or remove"
        className="inline-flex rounded-md border border-zinc-200 bg-zinc-100 p-0.5 text-xs"
        data-change-remove-switch=""
      >
        {([
          ["change", "Change"],
          ["remove", "Remove"],
        ] as const).map(([value, label]) => {
          const on = (value === "remove") === removing;
          return (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={on}
              data-change-remove={value}
              onClick={() => !on && setEditRemoving(value === "remove" ? [] : null)}
              className={cn(
                "rounded px-2 py-0.5 text-zinc-600 transition-colors",
                on && value === "remove" && "bg-red-700 font-medium text-white shadow-sm",
                on && value === "change" && "bg-white font-medium text-zinc-900 shadow-sm",
                !on && "hover:text-zinc-900"
              )}
            >
              {label}
            </button>
          );
        })}
      </div>
    </>
  ) : undefined;
  const handleChoiceChange = (next: ValidityChoice) => {
    setChoice(next);
    if (next === "frame" && currentEdit.frameIdent) void changeEditFrame(currentEdit.frameIdent);
  };

  const dataSourceCode = dataSources.find((d) => String(d.id) === currentEdit.dataSourceId)?.code ?? null;

  // Every save of this edit goes through its form's submit, whichever button
  // starts it. A save reaching into a relative or fixed frame is held and the
  // user is asked (useFixedFrameConfirmation); Confirm submits again, marked
  // confirmed so it passes; Cancel stores nothing.
  const { ask, dialog } = useFixedFrameConfirmation();
  const anchorRef = useRef<HTMLDivElement>(null);
  const confirmedRef = useRef(false);
  // A date outside the unit's existence (dateOutsideBounds) holds the save: the
  // field already says why, so nothing is sent.
  const dateBounds =
    existence?.length ? { from: existence[0].validFrom, to: existence[existence.length - 1].validTo } : undefined;
  const boundsFrom = dateBounds?.from;
  const boundsTo = dateBounds?.to;
  useGuardedEffect(
    () => {
      const form = anchorRef.current?.closest("form");
      if (!form) return;
      const bounds = boundsFrom && boundsTo ? { from: boundsFrom, to: boundsTo } : undefined;
      const onSubmit = (event: SubmitEvent) => {
        const data = new FormData(form);
        const from = data.get("valid_from") as string | null;
        const to = data.get("valid_to") as string | null;
        if (dateOutsideBounds(from, bounds) || dateOutsideBounds(to, bounds)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
        if (confirmedRef.current) {
          confirmedRef.current = false;
          return;
        }
        // The period submitted is the form's own valid_from/valid_to fields.
        const held = ask(from, to, () => {
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
    [ask, boundsFrom, boundsTo],
    "EditMetadataControls:askBeforeFixedFrameSave"
  );

  return (
    <>
      <Separator className="mt-1" />
      <div ref={anchorRef} hidden />
      {dialog}
      <TimeFramePanel
        idPrefix={fieldId}
        timeFrames={timeFrames}
        mode={mode}
        onModeChange={handleModeChange}
        choice={choice}
        onChoiceChange={handleChoiceChange}
        frameIdent={currentEdit.frameIdent ?? null}
        onFrameChange={(ident) => void changeEditFrame(ident)}
        validFrom={currentEdit.validFrom ?? null}
        validTo={currentEdit.validTo ?? null}
        onValidFromChange={(d) => setEditValidFrom(d)}
        onValidToChange={(d) => setEditValidTo(d === "infinity" ? null : d)}
        dataSources={dataSources}
        dataSourceCode={dataSourceCode}
        onDataSourceChange={(code) =>
          setEditDataSourceId(dataSources.find((d) => d.code === code)?.id?.toString() ?? null)
        }
        comment={currentEdit.editComment ?? null}
        onCommentChange={setEditComment}
        formFields
        dateBounds={dateBounds}
        timelineControls={changeRemoveSwitch}
        hideMetadata={removing}
        timeline={
          removing ? (
            <RemovalTimeline />
          ) : empty && pieces.length > 0 ? (
            <div className="space-y-1" data-edit-timeline="skeleton">
              <TimelineSkeleton
                pieces={pieces}
                picked={picked}
                onToggle={handlePick}
                unitStart={existence?.[0]?.validFrom}
              />
              <p className="text-xs text-zinc-600" data-edit-timeline-range="">
                {currentEdit.validFrom
                  ? `Fills ${currentEdit.validFrom} – ${currentEdit.validTo ?? "Present"}`
                  : "Tick the periods to fill"}
              </p>
            </div>
          ) : currentEdit.source && loaded && periods.length > 0 ? (
            <div className="space-y-1" data-edit-timeline="">
              <FieldTimeline periods={periods} selected={selected} onToggle={handleToggle} />
              <p className="text-xs text-zinc-600" data-edit-timeline-range="">
                {currentEdit.validFrom
                  ? `Changes ${currentEdit.validFrom} – ${currentEdit.validTo ?? "Present"}`
                  : "Tick the periods to change"}
              </p>
            </div>
          ) : undefined
        }
      />
    </>
  );
}
