import {Metadata} from "next";
import {notFound} from "next/navigation";
import {Separator} from "@/components/ui/separator";
import {getLegalUnitById} from "@/app/legal-units/[id]/legal-unit-requests";

export const metadata: Metadata = {
  title: "Legal Unit | Inspect"
}

export default async function LegalUnitInspectionPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id)

  if (!unit) {
    notFound()
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium">Data dump</h3>
        <p className="text-sm text-muted-foreground">
          This section shows the raw data we have on {unit?.name}.
        </p>
      </div>
      <Separator />
      <div>
        <pre className="mt-2 rounded-md bg-slate-950 p-4">
          <code className="text-white text-xs">{JSON.stringify(unit, null, 2)}</code>
        </pre>
      </div>
    </div>
  )
}
