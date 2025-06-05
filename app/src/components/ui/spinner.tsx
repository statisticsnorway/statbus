import { cn } from "@/lib/utils";

export function Spinner({ message, className }: { message?: string, className?: string }) {
  return (
    <div className={cn("flex flex-col justify-center items-center", className)}>
      <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-gray-900"></div>
      {message && <p className="mt-2 text-gray-700">{message}</p>}
    </div>
  );
}
