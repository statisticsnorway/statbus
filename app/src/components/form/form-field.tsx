import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import React, { useEffect, useState } from "react";

export function FormField({
  label,
  name,
  value,
  readonly,
  response,
}: {
  readonly label: string;
  readonly name: string;
  readonly value?: string | number | null;
  readonly readonly?: boolean;
  readonly response: UpdateResponse;
}) {
  const [inputValue, setInputValue] = useState(value ?? "");

  useEffect(() => {
    setInputValue(value ?? "");
  }, [value]);

  const error =
    response?.status === "error"
      ? response?.errors?.find((a) => a.path === name)
      : null;
  return (
    <div>
      <Label className="flex flex-col space-y-2">
        <span className="text-xs uppercase text-gray-600">{label}</span>
        <Input
          type="text"
          readOnly={readonly}
          name={name}
          value={inputValue}
          onChange={(e) => setInputValue(e.target.value)}
          autoComplete="off"
          className="read-only:opacity-80 read-only:focus:outline-none read-only:focus:ring-0 read-only:focus:shadow-none read-only:focus:border-zinc-200 bg-white"
        />
      </Label>
      {error ? (
        <span className="mt-2 block text-sm text-red-500">
          {error?.message}
        </span>
      ) : null}
    </div>
  );
}
