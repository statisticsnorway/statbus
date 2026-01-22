import { cn } from "@/lib/utils";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";

interface DetailsPageHeaderProps {
  title: string | null;
  subtitle?: string;
  className?: string;
  unitType?: "establishment" | "legal_unit" | "enterprise" | "enterprise_group";
  unitTypeLabel?: string;
}

export const DetailsPageHeader = ({
  title,
  subtitle,
  className,
  unitType,
  unitTypeLabel,
}: DetailsPageHeaderProps) => (
  <div
    className={cn(
      "space-y-0.5 border-b-2 border-gray-100 bg-gray-50 p-4",
      className
    )}
  >
    <div className="flex items-start justify-between gap-4">
      <div className="flex-1 min-w-0">
        <h2 className="text-2xl font-semibold tracking-tight">{title}</h2>
        <p className="text-sm">
          {subtitle ?? <span>Manage settings for {title}</span>}
        </p>
      </div>
      {unitType && (
        <div className="flex flex-col items-center gap-1 text-xs text-gray-600">
          <StatisticalUnitIcon type={unitType} className="h-8 w-8" />
          {unitTypeLabel && <span className="font-medium">{unitTypeLabel}</span>}
        </div>
      )}
    </div>
  </div>
);


interface DetailsPageHeaderSkeletonProps {
  className?: string;
}

export const DetailsPageHeaderSkeleton = ({
  className,
}: DetailsPageHeaderSkeletonProps) => (
  <div
    className={cn(
      "space-y-0.5 border-b-2 border-gray-100 bg-gray-50 p-4",
      className
    )}
  >
    <div className="h-8 w-40  bg-gray-50" />
    <div className="h-5 w-64  bg-gray-50" />
  </div>
);
