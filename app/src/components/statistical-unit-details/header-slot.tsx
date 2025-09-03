import {
  DetailsPageHeader,
  DetailsPageHeaderSkeleton,
} from "@/components/statistical-unit-details/details-page-header";
import { PostgrestError } from "@supabase/postgrest-js";
import { cn } from "@/lib/utils";

interface HeaderSlotProps {
  readonly id: string;
  readonly unit?: { name: string | null };
  readonly error: PostgrestError | null;
  readonly loading?: boolean;
  readonly className?: string;
}

export default function HeaderSlot({
  id,
  unit,
  error,
  loading,
  className,
}: HeaderSlotProps) {
  if (loading) {
    return <DetailsPageHeaderSkeleton className={className} />;
  }
  if (error) {
    return (
      <DetailsPageHeader
        title="Failed To Get Statistical Unit"
        subtitle={`Something unforeseen happened while looking for statistical unit with ID ${id}`}
        className={cn("", className)}
      />
    );
  }

  if (!unit) {
    return (
      <DetailsPageHeader
        title="Not Found"
        subtitle={`Could not find statistical unit with ID ${id}`}
        className={cn("", className)}
      />
    );
  }

  return (
    <DetailsPageHeader
      title={unit.name ?? "Unnamed"}
      className={cn("", className)}
    />
  );
}
