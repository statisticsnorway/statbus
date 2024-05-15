import { cn } from "@/lib/utils";
interface TableResultCountProps {
  total: number;
  pagination: { pageSize: number; pageNumber: number };
  className?: string;
}
export const TableResultCount = ({
  total,
  pagination,
  className,
}: TableResultCountProps) => {
  const startIndex = total
    ? (pagination.pageNumber - 1) * pagination.pageSize + 1
    : 0;
  const endIndex = total
    ? Math.min(pagination.pageNumber * pagination.pageSize, total)
    : 0;
  return (
    <span className={cn("indent-2.5", className)}>
      Showing {startIndex}-{endIndex} of total {total} results
    </span>
  );
};
