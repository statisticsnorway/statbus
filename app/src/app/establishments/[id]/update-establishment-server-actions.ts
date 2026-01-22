"use server";
import { getServerRestClient } from "@/context/RestClientStore";
import { revalidatePath } from "next/cache";
import { createServerLogger } from "@/lib/server-logger";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { getEditMetadata } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import {
  resolveSchemaByType,
  checkValidityBounds,
} from "@/components/form/helper-functions";

export async function updateEstablishment(
  id: string,
  schemaType: SchemaType,
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const schema = resolveSchemaByType(schemaType);
  const validatedFields = schema.safeParse(formData);
  if (!validatedFields.success) {
    return {
      status: "error",
      message: "failed to parse form data",
      errors: validatedFields.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }

  const { valid_from, valid_to } = validatedFields.data;

  try {
    const { error: metadataError, metadata } = await getEditMetadata(client);
    if (metadataError) return metadataError;
    
    // Handle image upload/delete
    let imageId: number | null | undefined = undefined;
    const deleteImage = formData.get("delete_image") === "true";
    const imageFile = formData.get("image") as File | null;
    
    if (deleteImage) {
      // User wants to delete the image
      imageId = null;
    } else if (imageFile && imageFile.size > 0) {
      // User uploaded a new image - store as binary (hex-encoded for PostgREST)
      const bytes = await imageFile.arrayBuffer();
      const buffer = Buffer.from(bytes);
      // PostgREST accepts bytea as hex-encoded string with \x prefix
      const hexData = "\\x" + buffer.toString("hex");
      
      const { data: imageData, error: imageError } = await client
        .from("image")
        .insert({
          data: hexData,
          type: imageFile.type,
        })
        .select("id")
        .single();
      
      if (imageError || !imageData) {
        const logger = await createServerLogger();
        logger.error(imageError, "failed to insert image");
        return {
          status: "error",
          message: imageError?.message || "Failed to upload image",
        };
      }
      
      imageId = imageData.id;
    }
    
    // Extract image-related fields that shouldn't be sent to database
    const { image, delete_image, ...dataFields } = validatedFields.data;
    
    const payload = { 
      ...dataFields, 
      ...metadata,
      ...(imageId !== undefined && { image_id: imageId })
    };
    
    const { data: overlappingRows, error: overlapError } = await client
      .from("establishment")
      .select("*")
      .eq("id", parseInt(id, 10))
      .lte("valid_from", valid_to)
      .gte("valid_to", valid_from);

    if (overlapError) {
      return {
        status: "error" as const,
        message: overlapError.message,
      };
    }

    if (overlappingRows && overlappingRows.length > 0) {
      const boundsError = checkValidityBounds(
        overlappingRows,
        valid_from,
        valid_to,
        "establishment"
      );
      if (boundsError) return boundsError;
      const response = await client
        .from("establishment__for_portion_of_valid")
        .update(payload)
        .eq("id", parseInt(id, 10));

      if (response.status >= 400) {
        return {
          status: "error",
          message: response.error?.message || response.statusText,
        };
      }
    } else {
      return {
        status: "error",
        message:
          "Cannot insert establishment. Only updates within the existing date range are allowed.",
      };
    }

    revalidatePath("/establishments/[id]", "page");
  } catch (error) {
    return { status: "error", message: "failed to update establishment" };
  }

  return { status: "success", message: "Establishment successfully updated" };
}

export async function updateEstablishmentImage(
  id: string,
  _prevState: any,
  formData: FormData
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const logger = await createServerLogger();

  try {
    const file = formData.get("image") as File;
    if (!file) {
      return {
        status: "error",
        message: "No image file provided",
      };
    }

    // Convert file to base64
    const bytes = await file.arrayBuffer();
    const buffer = Buffer.from(bytes);
    const base64Data = buffer.toString("base64");

    // Insert image into public.image table
    const { data: imageData, error: imageError } = await client
      .from("image")
      .insert({
        data: base64Data,
        type: file.type,
      })
      .select("id")
      .single();

    if (imageError || !imageData) {
      logger.error(imageError, "failed to insert image");
      return {
        status: "error",
        message: imageError?.message || "Failed to upload image",
      };
    }

    // Update only the currently valid temporal version
    // Note: This updates the specific temporal version that's currently in view
    // We need to find which temporal range is currently being viewed
    const today = new Date().toISOString().split('T')[0];
    
    const { error: updateError } = await client
      .from("establishment")
      .update({ image_id: imageData.id })
      .eq("id", parseInt(id, 10))
      .lte("valid_from", today)
      .gte("valid_to", today);

    if (updateError) {
      logger.error(updateError, "failed to update establishment image_id");
      return {
        status: "error",
        message: updateError.message,
      };
    }

    revalidatePath("/establishments/[id]", "page");
    return {
      status: "success",
      message: "Image uploaded successfully",
    };
  } catch (error) {
    logger.error(error, "failed to upload establishment image");
    return {
      status: "error",
      message: "Failed to upload image",
    };
  }
}

export async function deleteEstablishmentImage(
  id: string,
  _prevState: any
): Promise<UpdateResponse> {
  const client = await getServerRestClient();
  const logger = await createServerLogger();

  try {
    // Get current image_id before clearing it (from any temporal version)
    const { data: establishments, error: fetchError } = await client
      .from("establishment")
      .select("image_id")
      .eq("id", parseInt(id, 10))
      .limit(1);

    if (fetchError || !establishments || establishments.length === 0 || !establishments[0].image_id) {
      return {
        status: "error",
        message: "No image to delete",
      };
    }

    const imageId = establishments[0].image_id;

    // Clear image_id from ALL temporal versions of this establishment
    const { error: updateError } = await client
      .from("establishment")
      .update({ image_id: null })
      .eq("id", parseInt(id, 10));

    if (updateError) {
      logger.error(updateError, "failed to clear establishment image_id");
      return {
        status: "error",
        message: updateError.message,
      };
    }

    // Delete the image record (optional - could keep for audit trail)
    const { error: deleteError } = await client
      .from("image")
      .delete()
      .eq("id", imageId);

    if (deleteError) {
      logger.error(deleteError, "failed to delete image record");
      // Don't fail - image_id is already cleared
    }

    revalidatePath("/establishments/[id]", "page");
    return {
      status: "success",
      message: "Image deleted successfully",
    };
  } catch (error) {
    logger.error(error, "failed to delete establishment image");
    return {
      status: "error",
      message: "Failed to delete image",
    };
  }
}

export async function setPrimaryEstablishment(id: number) {
  "use server";
  const logger = await createServerLogger();
  const client = await getServerRestClient();
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
