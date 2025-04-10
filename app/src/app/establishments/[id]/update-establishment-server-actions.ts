"use server";
import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import { revalidatePath } from "next/cache";
import { createServerLogger } from "@/lib/server-logger";

export async function setPrimaryEstablishment(id: number) {
  "use server";
  const logger = await createServerLogger();
  const client = await createPostgRESTSSRClient();
  const { error } = await client.rpc(
    "set_primary_establishment_for_legal_unit",
    { establishment_id: id }
  );

  if (error) {
    logger.error(error, "failed to set primary establishment");
    return;
  }

  revalidatePath("/establishments/[id]", "page");
}
