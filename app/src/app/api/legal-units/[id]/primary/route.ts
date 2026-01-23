import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { createServerLogger } from "@/lib/server-logger";

interface CombineUnitsRequest {
  unit_id: number;
  valid_from?: string | null;
  valid_to?: string | null;
}

export async function POST(
  request: NextRequest,
  props: { readonly params: Promise<{ id: string }> }
) {
  const params = await props.params;

  const { id } = params;

  const logger = await createServerLogger();
  try {
    const body: CombineUnitsRequest = await request.json();
    const legalUnitId = parseInt(id, 10);

    if (!body?.unit_id || !legalUnitId) {
      logger.error(
        {
          body,
          legalUnitId,
        },
        "either enterprise id or legal unit id is missing"
      );
      return NextResponse.json(
        { error: "either enterprise id or legal unit id is missing" },
        { status: 400 }
      );
    }

    // Build RPC parameters - only include temporal params if provided
    const rpcParams: {
      legal_unit_id: number;
      enterprise_id: number;
      valid_from?: string;
      valid_to?: string;
    } = {
      legal_unit_id: legalUnitId,
      enterprise_id: body.unit_id,
    };

    // Add temporal parameters if provided (let database use defaults if not)
    if (body.valid_from) {
      rpcParams.valid_from = body.valid_from;
    }
    if (body.valid_to) {
      rpcParams.valid_to = body.valid_to;
    }

    const client = await getServerRestClient();
    const { data, error } = await client.rpc(
      "connect_legal_unit_to_enterprise",
      rpcParams
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
