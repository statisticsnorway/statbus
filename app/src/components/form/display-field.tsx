import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import React from "react";

export function DisplayFormField({
  label,
  name,
  value,
}: {
  readonly label: string;
  readonly name: string;
  readonly value?: string | number | null;
}) {
  return (
    <div>
      <Label className="flex flex-col space-y-2">
        <span className="text-xs uppercase text-gray-600">{label}</span>
        <Input
          type="text"
          readOnly
          name={name}
          value={value ?? ""}
          className="read-only:opacity-80 read-only:focus:outline-none read-only:focus:ring-0 read-only:focus:shadow-none read-only:focus:border-zinc-200 bg-white"
        />
      </Label>
    </div>
  );
}
