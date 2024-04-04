"use client";
import { User } from "lucide-react";
import { cn } from "@/lib/utils";

export default function ProfileAvatar({
  className,
}: {
  readonly className?: string;
}) {
  return (
    <a
      href="/profile"
      aria-label="Profile"
      className={cn(
        "flex h-7 w-7 items-center justify-center rounded-full bg-green-200 uppercase",
        className
      )}
    >
      <User size={16} />
    </a>
  );
}
