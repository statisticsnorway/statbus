"use client";
import { ArrowBigUp, Command, Menu } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

function showCommandPalette() {
  document.dispatchEvent(new CustomEvent("toggle-command-palette"));
}

export function CommandPaletteTriggerButton({
  className,
}: {
  readonly className?: string;
}) {
  return (
    <Button
      title="Open command palette"
      variant="outline"
      size="sm"
      type="button"
      className={cn("space-x-1 font-normal", className)}
      onClick={showCommandPalette}
    >
      <span>Command Palette</span>
      <span>(</span>
      <Command size={14} />
      <span>+</span>
      <ArrowBigUp size={18} />
      <span>+</span>
      <span>K</span>
      <span>)</span>
    </Button>
  );
}

export function CommandPaletteTriggerMobileMenuButton({
  className,
}: {
  readonly className?: string;
}) {
  return (
    <Button
      title="Open command palette"
      variant="ghost"
      type="button"
      className={cn("h-auto px-0 py-0", className)}
      onClick={showCommandPalette}
    >
      <Menu className="h-7 w-7" />
    </Button>
  );
}
