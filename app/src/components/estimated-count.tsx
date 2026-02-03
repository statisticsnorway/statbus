"use client";

import { useState, useCallback, MouseEvent } from "react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Button } from "@/components/ui/button";
import { Info, Loader2 } from "lucide-react";

interface EstimatedCountProps {
  readonly estimatedCount: number | null;
  readonly onGetExact?: () => Promise<number | null>;
  readonly className?: string;
}

/**
 * Displays an estimated count with a ~ prefix and a separate info button that opens
 * a popover explaining the estimate. The info button stops event propagation so it
 * works correctly when nested inside links.
 */
export function EstimatedCount({
  estimatedCount,
  onGetExact,
  className,
}: EstimatedCountProps) {
  const [exactCount, setExactCount] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isOpen, setIsOpen] = useState(false);

  const handleGetExact = useCallback(async () => {
    if (!onGetExact) return;
    setIsLoading(true);
    try {
      const count = await onGetExact();
      setExactCount(count);
    } finally {
      setIsLoading(false);
    }
  }, [onGetExact]);

  // Stop propagation to prevent parent link from capturing the click
  const handleTriggerClick = useCallback((e: MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsOpen((prev) => !prev);
  }, []);

  // Stop propagation for the "Get Exact Count" button too
  const handleGetExactClick = useCallback(async (e: MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    await handleGetExact();
  }, [handleGetExact]);

  // If we have the exact count, show it without the ~ prefix
  if (exactCount !== null) {
    return (
      <span className={className}>
        {exactCount.toLocaleString()}
      </span>
    );
  }

  // Show estimated count with ~ prefix and info popover
  if (estimatedCount === null) {
    return <span className={className}>-</span>;
  }

  return (
    <span className={className}>
      <span className="inline-flex items-center gap-1">
        <Popover open={isOpen} onOpenChange={setIsOpen}>
          <PopoverTrigger asChild>
            <button
              type="button"
              onClick={handleTriggerClick}
              className="inline-flex items-center hover:text-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 rounded"
              aria-label="Estimated count - click for details"
            >
              <Info className="h-3 w-3 text-gray-400" />
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-80">
            <div className="space-y-3">
              <h4 className="font-medium">Estimated Count</h4>
              <p className="text-sm text-gray-600">
                This count is estimated from database statistics for faster loading.
                The actual count may differ slightly.
              </p>
              {onGetExact && (
                <Button
                  onClick={handleGetExactClick}
                  disabled={isLoading}
                  variant="outline"
                  size="sm"
                  className="w-full"
                >
                  {isLoading ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Loading...
                    </>
                  ) : (
                    "Get Exact Count"
                  )}
                </Button>
              )}
              {isLoading && (
                <p className="text-xs text-gray-500 text-center">
                  This may take several seconds for large datasets...
                </p>
              )}
            </div>
          </PopoverContent>
        </Popover>
        <span>~{estimatedCount.toLocaleString()}</span>
      </span>
    </span>
  );
}
