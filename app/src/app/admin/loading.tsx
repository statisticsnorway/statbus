import { ChevronRight } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";

export default function Loading() {
  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col px-2 py-8 md:py-12">
      <div className="space-y-4">
        <div className="mb-3 flex items-center">
          <span className="text-2xl text-gray-500">Admin</span>
          <ChevronRight className="h-6 w-6 text-gray-400" />
          <Skeleton className="h-6 w-40" />
        </div>
        <div className="space-y-12">
          <Skeleton className="h-4 w-64" />
        <Skeleton className="h-[240px] w-full" />
        </div>
      </div>
    </main>
  );
}

