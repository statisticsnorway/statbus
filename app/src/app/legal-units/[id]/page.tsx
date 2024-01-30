import {Metadata} from "next";
import {createClient} from "@/lib/supabase/server";
import {notFound} from "next/navigation";

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
    <>
      <code className="text-xs">{JSON.stringify(legalUnit, null, 1)}</code>
    </>
  )
}
