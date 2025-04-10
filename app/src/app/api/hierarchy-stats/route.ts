import { NextRequest, NextResponse } from "next/server";
import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);

  const unitId = searchParams.get("unitId");
  const unitType = searchParams.get("unitType") as UnitType;

  if (!unitId || !unitType) {
    return NextResponse.json(
      { error: "Missing unitId or unitType" },
      { status: 400 }
    );
  }
  const client = await createPostgRESTSSRClient();
  const { data, error } = await client
    .rpc("statistical_unit_stats", {
      unit_id: parseInt(unitId, 10),
      unit_type: unitType,
    })
    .neq("unit_type", "establishment"); // Exclude establishments as their stats summary is the same as their stats

  if (error) {
    return NextResponse.json({ error: error.message });
  }
  return NextResponse.json(data);
}
