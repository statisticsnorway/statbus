import { cn } from "@/lib/utils";

export default function DataDump({
  data,
  title,
  className,
}: {
  readonly data: Object;
  readonly title?: string;
  readonly className?: string;
}) {
  return (
    <pre
      className={cn(
        "rounded-md bg-slate-950 p-4 text-xs text-white",
        className
      )}
    >
      <code>
        {title && <div className="mb-3">## {title}</div>}
        {JSON.stringify(data, null, 2)}
      </code>
    </pre>
  );
}
