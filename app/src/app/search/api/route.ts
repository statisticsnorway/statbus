import {createClient} from "@/lib/supabase/server";
import {NextResponse} from "next/server";

export async function GET(request: Request) {
  const {searchParams} = new URL(request.url)
  const client = createClient()
  const searchTerm = searchParams.get('q') ?? ""
  const activityCategoryCodes = searchParams.get('activity_category_codes')?.split(',') ?? []
  const regionCodes = searchParams.get('region_codes')?.split(',') ?? []

  console.info("legal units search filter:", {searchTerm, activityCategoryCodes, regionCodes})

  const {data: legalUnits, count, error} = await client
    .from('legal_unit')
    .select('tax_reg_ident, name', {count: 'exact'})
    .ilike('name', `*${searchTerm}*`)
    .limit(10)

  if (error) {
    return NextResponse.json({error})
  }

  return NextResponse.json({legalUnits, count})
}
