import {Metadata} from "next";
import {createClient} from "@/lib/supabase/server";
import {notFound} from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info-form";
import {Separator} from "@/components/ui/separator";

export const metadata: Metadata = {
  title: "Legal Unit | General Info"
}

export default async function LegalUnitGeneralInfoPage({params: {id}}: { params: { id: string } }) {
  const client = createClient()
  const {data: legalUnit} = await client
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .single()

  if (!legalUnit) {
    notFound()
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium">General Info</h3>
        <p className="text-sm text-muted-foreground">
          General information such as name, id, sector and primary activity.
        </p>
      </div>
      <Separator />
      <GeneralInfoForm values={legalUnit} />
      <div>
        <pre className="mt-2 rounded-md bg-slate-950 p-4">
          <code className="text-white text-xs">{JSON.stringify(legalUnit, null, 2)}</code>
        </pre>
      </div>
    </div>
  )
}
