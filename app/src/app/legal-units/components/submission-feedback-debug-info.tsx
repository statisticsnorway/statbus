import { cn } from "@/lib/utils";
import React from "react";
import DataDump from "@/components/data-dump";

export function SubmissionFeedbackDebugInfo({
  state,
}: {
  state: UpdateResponse;
}) {
  return state?.status ? (
    <DataDump
      className={cn(
        "block text-xs text-black",
        state.status === "success" ? "bg-green-100" : "bg-red-100"
      )}
      data={state}
    />
  ) : null;
}
