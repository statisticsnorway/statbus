import {UpdateResponse} from "@/app/legal-units/types";
import {cn} from "@/lib/utils";
import React from "react";

export function SubmissionFeedbackDebugInfo({state}: {
  state: UpdateResponse
}) {
  return state?.status ? (
    <small className="block">
            <pre
              className={cn("mt-2 rounded-md bg-red-100 p-4", state.status === "success" ? "bg-green-100" : "bg-red-100")}>
                <code className="text-xs">{JSON.stringify(state, null, 2)}</code>
            </pre>
    </small>
  ) : null
}
