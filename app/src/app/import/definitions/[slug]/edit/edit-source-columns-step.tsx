"use client";

import { useState, useCallback } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Spinner } from "@/components/ui/spinner";
import { X, Upload, Plus } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import type { Tables } from "@/lib/database.types";

interface EditSourceColumnsStepProps {
  sourceColumns: Tables<"import_source_column">[];
  /** Source column ids the definition accepts but does not import. */
  ignoredSourceColumnIds: Set<number>;
  onAddColumn: (columnName: string, ignored: boolean) => Promise<void>;
  onRemoveColumn: (sourceColumnId: number) => Promise<void>;
  onBack: () => void;
  onNext: () => void;
}

export function EditSourceColumnsStep({
  sourceColumns,
  ignoredSourceColumnIds,
  onAddColumn,
  onRemoveColumn,
  onBack,
  onNext,
}: EditSourceColumnsStepProps) {
  const [manualInput, setManualInput] = useState("");
  const [isDragging, setIsDragging] = useState(false);
  const [addingColumn, setAddingColumn] = useState(false);
  const [removingId, setRemovingId] = useState<number | null>(null);
  // A column no step reads: offer to accept it as ignored.
  const [unreadable, setUnreadable] = useState<{ name: string; message: string } | null>(null);

  // Adds a column; when the definition cannot read it, keeps it for the
  // "Add as ignored" choice instead of failing silently.
  const tryAdd = useCallback(
    async (name: string): Promise<boolean> => {
      try {
        await onAddColumn(name, false);
        return true;
      } catch (err) {
        setUnreadable({ name, message: err instanceof Error ? err.message : String(err) });
        return false;
      }
    },
    [onAddColumn],
  );

  const extractHeaders = useCallback(
    async (file: File) => {
      const formData = new FormData();
      formData.append("file", file);
      try {
        const res = await fetch("/api/import/headers", {
          method: "POST",
          body: formData,
        });
        const json = await res.json();
        if (!res.ok) {
          toast({ title: json.error || "Failed to parse file", variant: "destructive" });
          return;
        }
        const headers = json.headers as string[];
        const existing = new Set(sourceColumns.map((c) => c.column_name));
        const newHeaders = headers.filter((h) => !existing.has(h));
        let added = 0;
        for (const h of newHeaders) {
          if (await tryAdd(h)) added++;
          else break;
        }
        toast({ title: `Added ${added} new column(s) from file` });
      } catch {
        toast({ title: "Failed to read file", variant: "destructive" });
      }
    },
    [sourceColumns, tryAdd],
  );

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) extractHeaders(file);
    e.target.value = "";
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) extractHeaders(file);
  };

  const handleAddManual = async () => {
    const name = manualInput.trim();
    if (!name) return;
    if (sourceColumns.some((c) => c.column_name === name)) {
      toast({ title: `Column "${name}" already exists`, variant: "destructive" });
      return;
    }
    setAddingColumn(true);
    try {
      if (await tryAdd(name)) setManualInput("");
    } finally {
      setAddingColumn(false);
    }
  };

  const handleRemove = async (col: Tables<"import_source_column">) => {
    setRemovingId(col.id);
    try {
      await onRemoveColumn(col.id);
    } finally {
      setRemovingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <div
        className={`border-2 border-dashed rounded-lg p-8 text-center transition-colors ${
          isDragging ? "border-primary bg-primary/5" : "border-muted-foreground/25"
        }`}
        onDragOver={(e) => {
          e.preventDefault();
          setIsDragging(true);
        }}
        onDragLeave={() => setIsDragging(false)}
        onDrop={handleDrop}
      >
        <Upload className="mx-auto h-8 w-8 text-muted-foreground mb-2" />
        <p className="text-sm text-muted-foreground mb-3">
          Drop a CSV or Excel file to add columns
        </p>
        <Label htmlFor="edit-file-upload" className="cursor-pointer">
          <Button variant="outline" asChild>
            <span>
              <Upload className="mr-2 h-4 w-4" />
              Choose file
            </span>
          </Button>
        </Label>
        <input
          id="edit-file-upload"
          type="file"
          accept=".csv,.tsv,.txt"
          className="hidden"
          onChange={handleFileChange}
        />
      </div>

      <div className="space-y-2">
        <Label>Add column manually</Label>
        <div className="flex gap-2">
          <Input
            value={manualInput}
            onChange={(e) => setManualInput(e.target.value)}
            placeholder="Column name"
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                handleAddManual();
              }
            }}
          />
          <Button
            variant="outline"
            onClick={handleAddManual}
            disabled={!manualInput.trim() || addingColumn}
          >
            {addingColumn ? <Spinner className="h-4 w-4" /> : <Plus className="h-4 w-4" />}
          </Button>
        </div>
      </div>

      {unreadable && (
        <div className="rounded border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800 space-y-2">
          <p>
            <span className="font-mono">{unreadable.name}</span>: {unreadable.message}
          </p>
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={async () => {
                await onAddColumn(unreadable.name, true);
                setUnreadable(null);
                setManualInput("");
              }}
            >
              Add as ignored
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setUnreadable(null)}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {sourceColumns.length > 0 && (
        <div className="space-y-2">
          <Label>Source columns ({sourceColumns.length})</Label>
          <div className="space-y-1">
            {sourceColumns.map((col) => (
              <div
                key={col.id}
                className="flex items-center justify-between bg-muted/50 rounded px-3 py-1.5 text-sm"
              >
                <span className="font-mono">
                  {col.column_name}
                  {ignoredSourceColumnIds.has(col.id) && (
                    <span className="ml-2 rounded border border-amber-300 bg-amber-50 px-1.5 text-xs text-amber-700">
                      Ignored
                    </span>
                  )}
                </span>
                <button
                  type="button"
                  onClick={() => handleRemove(col)}
                  disabled={removingId === col.id}
                  className="text-muted-foreground hover:text-destructive transition-colors"
                >
                  {removingId === col.id ? (
                    <Spinner className="h-4 w-4" />
                  ) : (
                    <X className="h-4 w-4" />
                  )}
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="flex justify-between">
        <Button variant="outline" onClick={onBack}>
          Back
        </Button>
        <Button onClick={onNext} disabled={sourceColumns.length === 0}>
          Next
        </Button>
      </div>
    </div>
  );
}
