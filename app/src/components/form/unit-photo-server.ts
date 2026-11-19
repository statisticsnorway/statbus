// Used by the unit edit server actions ("use server" modules) only.
import type { getServerRestClient } from "@/context/RestClientStore";
import { createServerLogger } from "@/lib/server-logger";

type RestClient = Awaited<ReturnType<typeof getServerRestClient>>;

/**
 * The photo change an edit form carries: `undefined` leaves the unit's photo as it
 * is, `null` removes it from the edited period, a number is the newly stored photo.
 */
export type PhotoChange = number | null | undefined;

/**
 * Reads the photo field of a unit's edit form and stores a new photo when one was
 * chosen. The browser has already cropped and scaled it (@/lib/unit-photo); the
 * database refuses one over 256 KB and checks its magic bytes.
 */
export async function storeUnitPhoto(
  client: RestClient,
  formData: FormData
): Promise<{ photo: PhotoChange } | { error: string }> {
  if (formData.get("delete_image") === "true") return { photo: null };
  const file = formData.get("image") as File | null;
  if (!file || file.size === 0) return { photo: undefined };

  // PostgREST accepts bytea as hex with a \x prefix.
  const hexData = "\\x" + Buffer.from(await file.arrayBuffer()).toString("hex");
  const { data, error } = await client
    .from("image")
    .insert({ data: hexData, type: file.type })
    .select("id")
    .single();
  if (error || !data) {
    (await createServerLogger()).error(error, "failed to store unit photo");
    return { error: error?.message || "The photo could not be stored" };
  }
  return { photo: data.id };
}

/**
 * Removes a photo stored for an edit that then failed. No unit refers to it, so the
 * database's cleanup (public.image_drop_unreferenced), which runs when a unit stops
 * referring to a photo, never sees it.
 */
export async function discardUnsavedPhoto(client: RestClient, photo: PhotoChange) {
  if (typeof photo !== "number") return;
  const { error } = await client.from("image").delete().eq("id", photo);
  if (error) (await createServerLogger()).error(error, "failed to discard unsaved photo");
}
