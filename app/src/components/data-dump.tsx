import {cn} from "@/lib/utils";

export default function DataDump({data, title, className}: { readonly data: Object, readonly title?: string, readonly className?: string }) {
  return (
    <pre className={cn("text-white text-xs rounded-md bg-slate-950 p-4", className)}>
      <code>
        {
          title && <div className="mb-3">## {title}</div>
        }
        {
          JSON.stringify(data, null, 2)
        }
      </code>
    </pre>
  )
}
