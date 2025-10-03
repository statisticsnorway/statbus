import { cn } from "@/lib/utils";
import { useEffect } from "react";
import { useToast } from "@/hooks/use-toast";

export function SubmissionFeedbackDebugInfo({
  state,
}: {
  state: UpdateResponse;
}) {
  const { toast } = useToast();

  useEffect(() => {
    if (state?.status) {
      const isError = state.status === "error";
      toast({
        variant: "default",
        title: isError ? "Error" : "Success",
        description: `${state.message}`,
        className: `${
          isError
            ? "border-red-700 bg-red-100 text-red-700"
            : "border-green-700 bg-green-100 text-green-700"
        }`,
      });
    }
  }, [state, toast]);

  return null;
}
