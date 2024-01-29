import {createClient} from "@/lib/supabase/server";
import {notFound} from "next/navigation";

export default async function Page({params}: { params: { id: string } }) {
  const client = createClient()
  const {data: legalUnit} = await client
    .from("legal_unit")
    .select("*")
    .eq("tax_reg_ident", params.id)
    .single()

  if (!legalUnit) {
    notFound()
  }

  return (
    <div className="p-6 space-y-3">
      <h1 className="text-xl text-center">{legalUnit?.name}</h1>

      <div className="p-4 bg-amber-100">
        <small>
          <code>{JSON.stringify(legalUnit, null, 1)}</code>
        </small>
      </div>
    </div>
  )
}
