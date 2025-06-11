import React, { ReactNode } from "react";
import { cn } from "@/lib/utils";

export const InfoBox = ({
  children,
  className,
  variant,
}: {
  readonly children: ReactNode;
  readonly className?: string;
  readonly variant?: "error" | "info"; // Added variant prop
}) => (
  <div
    className={cn(
      "space-y-6 p-4 leading-loose border-2", // Common styles
      variant === "error"
        ? "bg-red-50 border-red-200 text-red-700" // Error variant styles
        : "bg-amber-50 border-amber-100", // Default/info styles
      className
    )}
  >
    {children}
  </div>
);
