import {createClient} from "@/lib/supabase/server";

export default async function LegalUnitHeader({ params: { id }}: { params: { id: string } }) {
  const client = createClient()
  const {data: legalUnit} = await client
    .from("legal_unit")
    .select("*")
    .eq("tax_reg_ident", id)
    .single()


  return (
    <div className="space-y-0.5">
      <h2 className="text-2xl font-bold tracking-tight">{legalUnit?.name || id}</h2>
      <p className="text-muted-foreground">
        Manage settings for legal unit {id}.
      </p>
    </div>
  )
}
