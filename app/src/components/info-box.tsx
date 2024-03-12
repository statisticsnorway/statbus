import React, { ReactNode } from "react";
import { cn } from "@/lib/utils";

export const InfoBox = ({
  children,
  className,
}: {
  readonly children: ReactNode;
  readonly className?: string;
}) => (
  <div className={cn("space-y-6 bg-amber-100 p-6 leading-loose", className)}>
    {children}
  </div>
);
