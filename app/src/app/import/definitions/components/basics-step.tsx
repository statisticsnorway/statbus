"use client";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import type { Enums } from "@/lib/database.types";

const IMPORT_MODES: { value: Enums<"import_mode">; label: string }[] = [
  { value: "legal_unit", label: "Legal Units" },
  { value: "establishment_formal", label: "Establishments (with Legal Unit)" },
  { value: "establishment_informal", label: "Establishments (without Legal Unit)" },
  { value: "generic_unit", label: "Generic Units" },
  { value: "legal_relationship", label: "Legal Relationships" },
];

const IMPORT_STRATEGIES: { value: Enums<"import_strategy">; label: string }[] = [
  { value: "insert_or_replace", label: "Insert or Replace" },
  { value: "insert_only", label: "Insert Only" },
  { value: "replace_only", label: "Replace Only" },
  { value: "insert_or_update", label: "Insert or Update" },
  { value: "update_only", label: "Update Only" },
];

interface BasicsStepProps {
  name: string;
  onNameChange: (name: string) => void;
  mode: Enums<"import_mode"> | null;
  onModeChange: (mode: Enums<"import_mode">) => void;
  strategy: Enums<"import_strategy">;
  onStrategyChange: (strategy: Enums<"import_strategy">) => void;
  validTimeFrom: Enums<"import_valid_time_from">;
  onValidTimeFromChange: (v: Enums<"import_valid_time_from">) => void;
  note: string;
  onNoteChange: (note: string) => void;
  onNext: () => void;
  isEditMode?: boolean;
}

export function BasicsStep({
  name,
  onNameChange,
  mode,
  onModeChange,
  strategy,
  onStrategyChange,
  validTimeFrom,
  onValidTimeFromChange,
  note,
  onNoteChange,
  onNext,
  isEditMode,
}: BasicsStepProps) {
  const canProceed = name.trim() && mode;

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Label htmlFor="def-name">Name *</Label>
        <Input
          id="def-name"
          value={name}
          onChange={(e) => onNameChange(e.target.value)}
          placeholder="e.g. Legal Units from Tax Registry"
        />
      </div>

      <div className="space-y-2">
        <Label>Import Mode *</Label>
        <RadioGroup
          value={mode ?? ""}
          onValueChange={(v) => onModeChange(v as Enums<"import_mode">)}
          disabled={isEditMode}
          className="space-y-2"
        >
          {IMPORT_MODES.map((m) => (
            <div key={m.value} className="flex items-center space-x-2">
              <RadioGroupItem value={m.value} id={`mode-${m.value}`} />
              <Label htmlFor={`mode-${m.value}`} className="font-normal cursor-pointer">
                {m.label}
              </Label>
            </div>
          ))}
        </RadioGroup>
      </div>

      <div className="space-y-2">
        <Label htmlFor="def-strategy">Import Strategy</Label>
        <Select value={strategy} onValueChange={(v) => onStrategyChange(v as Enums<"import_strategy">)}>
          <SelectTrigger id="def-strategy">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {IMPORT_STRATEGIES.map((s) => (
              <SelectItem key={s.value} value={s.value}>
                {s.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-2">
        <Label>Valid Time From *</Label>
        <RadioGroup
          value={validTimeFrom}
          onValueChange={(v) => onValidTimeFromChange(v as Enums<"import_valid_time_from">)}
          disabled={isEditMode}
          className="space-y-2"
        >
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="job_provided" id="vtf-job" />
            <Label htmlFor="vtf-job" className="font-normal cursor-pointer">
              Job provided (user selects time context when creating job)
            </Label>
          </div>
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="source_columns" id="vtf-source" />
            <Label htmlFor="vtf-source" className="font-normal cursor-pointer">
              Source columns (file contains valid_from/valid_to)
            </Label>
          </div>
        </RadioGroup>
      </div>

      <div className="space-y-2">
        <Label htmlFor="def-note">Note (optional)</Label>
        <Textarea
          id="def-note"
          value={note}
          onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) => onNoteChange(e.target.value)}
          placeholder="Description of this import definition..."
          rows={3}
        />
      </div>

      <div className="flex justify-end">
        <Button onClick={onNext} disabled={!canProceed}>
          Next
        </Button>
      </div>
    </div>
  );
}
