"use client";

import { useRef, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useFixedFrameConfirmation } from "@/components/fixed-frame-confirmation";
import { TimeFramePanel, type TimeFramePanelMode, type ValidityChoice } from "@/components/time-frame-panel";
import { useDetailsPageData, useEditManager } from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { Separator } from "@/components/ui/separator";
import { useChangeEditFrame } from "./use-start-edit";
import { FieldTimeline, useFieldTimeline } from "./field-timeline-view";
import { opensInTimeline, periodsInRange, selectionRange, toggleSelection } from "./field-timeline";

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

  // Simple always means a frame: the frame's dates come back.
  const handleModeChange = (next: TimeFramePanelMode) => {
    setMode(next);
    if (next === "simple") handleChoiceChange("frame");
  };
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
        timeline={
          currentEdit.source && loaded && periods.length > 0 ? (
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
