import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { Loader } from "lucide-react";
import * as React from "react";

export function FilterSkeleton({
  title,
  className,
}: {
  title: string;
  className?: string;
}) {
  return (
    <Button
      variant="outline"
      className={cn("p-2 h-9 space-x-2 border-dashed", className)}
    >
      <Loader className="mr-2 h-4 w-4 animate-spin" />
      {title}
    </Button>
  );
}
