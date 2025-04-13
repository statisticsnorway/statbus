import { NextRequest, NextResponse } from "next/server";
import { getServerClient } from "@/context/ClientStore";
import { createServerLogger } from "@/lib/server-logger";

export async function POST(request: NextRequest, props: { readonly params: Promise<{ id: string }> }) {
  const params = await props.params;

  const {
    id
  } = params;

  const logger = await createServerLogger();
  try {
    const enterprise: { unit_id: number } = await request.json();
    const legalUnitId = parseInt(id, 10);

    if (!enterprise?.unit_id || !legalUnitId) {
      logger.error(
        {
          enterprise,
          legalUnitId,
        },
        "either enterprise id or legal unit id is missing"
      );
      return NextResponse.json(
        { error: "either enterprise id or legal unit id is missing" },
        { status: 400 }
      );
    }

    const client = await getServerClient();
    const { data, error } = await client.rpc(
      "connect_legal_unit_to_enterprise",
      {
        legal_unit_id: legalUnitId,
        enterprise_id: enterprise.unit_id,
      }
    );

    if (error) {
      logger.error(error, "failed to connect legal unit to enterprise");
      return NextResponse.json(
        { error: "failed to connect legal unit to enterprise" },
        { status: 500 }
      );
    }

    return NextResponse.json(data);
  } catch (e) {
    logger.error(e, "failed to connect legal unit to enterprise");
    return NextResponse.json(
      { error: "failed to connect legal unit to enterprise" },
      { status: 500 }
    );
  }
}
