import {cn} from "@/lib/utils";

export const DetailsPageHeader = ({name, className}: { name?: string | null, className?: string }) => (
  <div className={cn("space-y-0.5 bg-gray-50 border-b-2 border-gray-100 p-4", className)}>
    <h2 className="text-2xl font-semibold tracking-tight">
      {name || "Unnamed Organization"}
    </h2>
    <p className="text-sm">
      Manage settings for {name || "Unnamed Organization"}
    </p>
  </div>
)
