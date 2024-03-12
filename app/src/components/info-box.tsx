import React, { ReactNode } from "react";
import { cn } from "@/lib/utils";

export const InfoBox = ({
  children,
  className,
}: {
  readonly children: ReactNode;
  readonly className?: string;
}) => (
  <div
    className={cn(
      "space-y-6 bg-amber-50 border-2 p-4 border-amber-100 leading-loose",
      className
    )}
  >
    {children}
  </div>
);
