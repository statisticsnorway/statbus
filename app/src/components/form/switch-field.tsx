"use client";
import { Label } from "@/components/ui/label";
import { ReactNode } from "react";
import { Switch } from "../ui/switch";

interface SwitchFieldProps {
  name: string;
  label: string | ReactNode;
  value?: boolean;
  response?: UpdateResponse;
}

export function SwitchField({
  name,
  label,
  value,
  response,
}: SwitchFieldProps) {
  const error =
    response?.status === "error"
      ? response?.errors?.find((a) => a.path === name)
      : null;

  return (
    <div className="flex items-center justify-between space-x-2">
      <Label className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
        {label}
      </Label>
      <Switch
        key={String(value)}
        name={name}
        defaultChecked={Boolean(value)}
        aria-invalid={!!error}
        className="data-[state=checked]:bg-green-500 m-0"
      />
    </div>
  );
}
