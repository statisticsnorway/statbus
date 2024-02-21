import {cn} from "@/lib/utils";

export default function DataDump({data, className}: { readonly data: Object, readonly className?: string }) {
  return (
    <pre className={cn("mt-2 rounded-md bg-slate-950 p-4", className)}>
      <code className="text-white text-xs">
        {
          JSON.stringify(data, null, 2)
        }
      </code>
    </pre>
  )
}
