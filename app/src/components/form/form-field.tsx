import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import React from "react";

export function FormField({
  label,
  name,
  value,
  readonly,
  response,
}: {
  readonly label: string;
  readonly name: string;
  readonly value?: string | null;
  readonly readonly?: boolean;
  readonly response: UpdateResponse;
}) {
  const error =
    response?.status === "error"
      ? response?.errors?.find((a) => a.path === name)
      : null;
  return (
    <div>
      <Label className="block space-y-2">
        <span className="text-xs uppercase text-gray-600">{label}</span>
        <Input
          type="text"
          disabled={readonly}
          name={name}
          defaultValue={value ?? ""}
          autoComplete="off"
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
