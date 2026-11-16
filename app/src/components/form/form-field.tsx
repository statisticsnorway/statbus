import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import React, { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { DIFFERS } from "./edit-payload";

export function FormField({
  label,
  name,
  value,
  readonly,
  response,
  placeholder,
  type,
}: {
  readonly label: string;
  readonly name: string;
  readonly value?: string | number | null;
  readonly readonly?: boolean;
  readonly response: UpdateResponse;
  readonly placeholder?: string;
  readonly type?: string;
}) {
  const [inputValue, setInputValue] = useState(value ?? "");

  useGuardedEffect(
    () => {
      setInputValue(value ?? "");
    },
    [value],
    "FormField:syncvalue"
  );

  const error =
    response?.status === "error"
      ? response?.errors?.find((a) => a.path === name)
      : null;
  return (
    <div>
      <Label className="flex flex-col space-y-2">
        <span className="text-xs uppercase text-gray-600">{label}</span>
        <Input
          type={type ?? "text"}
          readOnly={readonly}
          placeholder={inputValue === DIFFERS ? "Differs" : (placeholder ?? "")}
          value={inputValue === DIFFERS ? "" : inputValue}
          onChange={(e) => setInputValue(e.target.value)}
          autoComplete="off"
          className={`read-only:opacity-80 read-only:focus:outline-none read-only:focus:ring-0 read-only:focus:shadow-none read-only:focus:border-zinc-200 bg-white ${inputValue === DIFFERS ? "placeholder:text-amber-800" : ""}`}
        />
        {/* The posted value: DIFFERS keeps each period's own (edit-payload). */}
        <input type="hidden" name={name} value={inputValue} />
      </Label>
      {error ? (
        <span className="mt-2 block text-sm text-red-500">
          {error?.message}
        </span>
      ) : null}
    </div>
  );
}
