"use client";

import { Label } from "../ui/label";
import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "../ui/select";

interface Option {
  value: string;
  label: string;
}

interface SelectFieldProps {
  name: string;
  label: string;
  options: Option[];
  value?: string | null;
  response?: UpdateResponse;
  placeholder?: string;
}

export function SelectField({
  name,
  label,
  options,
  value,
  response,
  placeholder = "Select an option...",
}: SelectFieldProps) {
  const [selectedValue, setSelectedValue] = useState(value ?? "");

  useGuardedEffect(
    () => {
      setSelectedValue(value ?? "");
    },
    [value],
    "SelectFormField:syncvalue"
  );

  const error =
    response?.status === "error"
      ? response?.errors?.find((a) => a.path === name)
      : null;

  return (
    <div className="flex flex-col space-y-2 w-full">
      <Label className="flex flex-col space-y-2">
        <span className="text-xs uppercase text-gray-600">{label}</span>
      </Label>
      <input name={name} type="hidden" value={selectedValue} />
      <Select
        value={selectedValue}
        onValueChange={(value) => setSelectedValue(value)}
      >
        <SelectTrigger className="w-full">
          <SelectValue placeholder={placeholder} />
        </SelectTrigger>
        <SelectContent>
          {options.map((option) => (
            <SelectItem key={option.value} value={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {error ? (
        <span className="block text-sm text-red-500">{error?.message}</span>
      ) : null}
    </div>
  );
}
