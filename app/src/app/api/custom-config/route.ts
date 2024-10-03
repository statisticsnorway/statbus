import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/utils/supabase/server";
import { createServerLogger } from "@/lib/server-logger";

export async function GET(request: NextRequest) {
  const logger = await createServerLogger();
  const client = createClient();

  try {
    const statDefinitionResponse = await client
      .from("stat_definition_ordered")
      .select();

    if (statDefinitionResponse.error) {
      throw new Error("failed to get stat definitions", {
        cause: statDefinitionResponse.error,
      });
    }

    const externalIdentTypeResponse = await client
      .from("external_ident_type_ordered")
      .select();

    if (externalIdentTypeResponse.error) {
      throw new Error("failed to get external ident types", {
        cause: externalIdentTypeResponse.error,
      });
    }

    const customConfig = {
      statDefinitions: statDefinitionResponse.data,
      externalIdentTypes: externalIdentTypeResponse.data,
    };

    return NextResponse.json(customConfig);
  } catch (error: any) {
    logger.error(error);

    return NextResponse.json(
      {
        error: "failed to get custom config",
      },
      { status: 500 }
    );
  }
}
