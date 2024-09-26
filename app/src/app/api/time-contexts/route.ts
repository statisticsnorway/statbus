import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServerLogger } from "@/lib/server-logger";

export async function GET(_request: Request) {
  const logger = await createServerLogger();
  const res = await createClient()
    .from("time_context")
    .select()
    .eq("scope", "input_and_query");

  if (res.error) {
    logger.error(
      new Error("failed to get time context", { cause: res.error })
    );
    return NextResponse.json(
      {
        error: "failed to get time context",
      },
      { status: 500 }
    );
  }

  return NextResponse.json(res.data);
}
