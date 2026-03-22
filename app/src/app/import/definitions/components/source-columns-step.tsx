"use client";

import { useState, useCallback } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { X, Upload, Plus } from "lucide-react";
import { toast } from "@/hooks/use-toast";

interface SourceColumnsStepProps {
  columns: string[];
  onColumnsChange: (columns: string[]) => void;
  onBack: () => void;
  onNext: () => void;
}

export function SourceColumnsStep({
  columns,
  onColumnsChange,
  onBack,
  onNext,
}: SourceColumnsStepProps) {
  const [manualInput, setManualInput] = useState("");
  const [isDragging, setIsDragging] = useState(false);

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
        // Merge with existing, preserving order and avoiding duplicates
        const existing = new Set(columns);
        const merged = [...columns, ...headers.filter((h) => !existing.has(h))];
        onColumnsChange(merged);
        toast({ title: `Detected ${headers.length} column(s) from file` });
      } catch {
        toast({ title: "Failed to read file", variant: "destructive" });
      }
    },
    [columns, onColumnsChange],
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

  const addManualColumn = () => {
    const name = manualInput.trim();
    if (!name) return;
    if (columns.includes(name)) {
      toast({ title: `Column "${name}" already exists`, variant: "destructive" });
      return;
    }
    onColumnsChange([...columns, name]);
    setManualInput("");
  };

  const removeColumn = (index: number) => {
    onColumnsChange(columns.filter((_, i) => i !== index));
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
          Drop a CSV or Excel file to auto-detect columns
        </p>
        <Label htmlFor="file-upload" className="cursor-pointer">
          <Button variant="outline" asChild>
            <span>
              <Upload className="mr-2 h-4 w-4" />
              Choose file
            </span>
          </Button>
        </Label>
        <input
          id="file-upload"
          type="file"
          accept=".csv,.tsv,.txt,.xlsx,.xls"
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
                addManualColumn();
              }
            }}
          />
          <Button variant="outline" onClick={addManualColumn} disabled={!manualInput.trim()}>
            <Plus className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {columns.length > 0 && (
        <div className="space-y-2">
          <Label>Source columns ({columns.length})</Label>
          <div className="space-y-1">
            {columns.map((col, index) => (
              <div
                key={col}
                className="flex items-center justify-between bg-muted/50 rounded px-3 py-1.5 text-sm"
              >
                <span className="font-mono">{col}</span>
                <button
                  type="button"
                  onClick={() => removeColumn(index)}
                  className="text-muted-foreground hover:text-destructive transition-colors"
                >
                  <X className="h-4 w-4" />
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
        <Button onClick={onNext} disabled={columns.length === 0}>
          Next
        </Button>
      </div>
    </div>
  );
}
