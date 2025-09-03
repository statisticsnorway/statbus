import { cn } from "@/lib/utils";

interface DetailsPageHeaderProps {
  title: string | null;
  subtitle?: string;
  className?: string;
}

export const DetailsPageHeader = ({
  title,
  subtitle,
  className,
}: DetailsPageHeaderProps) => (
  <div
    className={cn(
      "space-y-0.5 border-b-2 border-gray-100 bg-gray-50 p-4",
      className
    )}
  >
    <h2 className="text-2xl font-semibold tracking-tight">{title}</h2>
    <p className="text-sm">
      {subtitle ?? <span>Manage settings for {title}</span>}
    </p>
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
