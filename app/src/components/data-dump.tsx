import {cn} from "@/lib/utils";

export default function DataDump({data, className}: { readonly data: Object, readonly className?: string }) {
  return (
    <pre className={cn("text-white text-xs rounded-md bg-slate-950 p-4", className)}>
      <code>
        {
          JSON.stringify(data, null, 2)
        }
      </code>
    </pre>
  )
}
