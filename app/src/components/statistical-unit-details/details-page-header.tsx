import {cn} from "@/lib/utils";

interface DetailsPageHeaderProps {
  title: string | null;
  subtitle?: string;
  className?: string;
}

export const DetailsPageHeader = ({title, subtitle, className}: DetailsPageHeaderProps) => (
  <div className={cn("space-y-0.5 bg-gray-50 border-b-2 border-gray-100 p-4", className)}>
    <h2 className="text-2xl font-semibold tracking-tight">
      {title}
    </h2>
    <p className="text-sm">
      {subtitle ?? <span>Manage settings for {title}</span>}
    </p>
  </div>
)
