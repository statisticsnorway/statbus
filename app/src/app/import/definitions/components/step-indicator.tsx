"use client";

import { cn } from "@/lib/utils";

const STEPS = ["Basics", "Columns", "Mappings", "Summary"] as const;

interface StepIndicatorProps {
  currentStep: number;
  onStepClick?: (step: number) => void;
}

export function StepIndicator({ currentStep, onStepClick }: StepIndicatorProps) {
  return (
    <nav aria-label="Progress" className="mb-8">
      <ol className="flex items-center justify-between">
        {STEPS.map((label, index) => {
          const isCompleted = index < currentStep;
          const isCurrent = index === currentStep;
          return (
            <li key={label} className="flex items-center">
              <button
                type="button"
                onClick={() => onStepClick?.(index)}
                disabled={!onStepClick || index > currentStep}
                className={cn(
                  "flex items-center gap-2 text-sm font-medium transition-colors",
                  isCurrent && "text-primary",
                  isCompleted && "text-primary cursor-pointer",
                  !isCurrent && !isCompleted && "text-muted-foreground",
                )}
              >
                <span
                  className={cn(
                    "flex h-7 w-7 items-center justify-center rounded-full border-2 text-xs font-bold",
                    isCurrent && "border-primary bg-primary text-primary-foreground",
                    isCompleted && "border-primary bg-primary/10 text-primary",
                    !isCurrent && !isCompleted && "border-muted-foreground/30",
                  )}
                >
                  {isCompleted ? "\u2713" : index + 1}
                </span>
                <span className="hidden sm:inline">{label}</span>
              </button>
              {index < STEPS.length - 1 && (
                <div
                  className={cn(
                    "mx-2 h-0.5 w-8 sm:w-16",
                    isCompleted ? "bg-primary" : "bg-muted-foreground/20",
                  )}
                />
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
