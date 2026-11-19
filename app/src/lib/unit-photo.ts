/**
 * A unit's photo is how a field worker recognises a unit on the next visit: a shop
 * front, a sign, a person met on the street. The whole picture is kept, as the user
 * framed it, scaled so its longest side is at most UNIT_PHOTO_MAX_SIDE, as JPEG; a few
 * photos per unit then never weigh on the database. The database refuses anything
 * over 256 KB (public.image image_size_limit) and deletes a photo no unit shows any
 * more (admin.image_released).
 */
export const UNIT_PHOTO_MAX_SIDE = 800;

/** The database's limit (public.image image_size_limit); quality steps down to fit. */
export const UNIT_PHOTO_MAX_BYTES = 262144;

const JPEG_QUALITIES = [0.85, 0.75, 0.65, 0.55, 0.45];

/** The size of a width x height picture scaled down so neither side exceeds maxSide. */
export function fitWithin(width: number, height: number, maxSide: number) {
  const scale = Math.min(1, maxSide / Math.max(width, height));
  return {
    width: Math.round(width * scale),
    height: Math.round(height * scale),
  };
}

/**
 * Scales a picture the user chose to fit UNIT_PHOTO_MAX_SIDE and encodes it as JPEG
 * under UNIT_PHOTO_MAX_BYTES, lowering the quality step by step when needed. Runs in
 * the browser.
 */
export async function toUnitPhoto(file: File): Promise<File> {
  const bitmap = await createImageBitmap(file, {
    imageOrientation: "from-image",
  });
  try {
    const { width, height } = fitWithin(
      bitmap.width,
      bitmap.height,
      UNIT_PHOTO_MAX_SIDE
    );
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("This browser cannot draw the photo");
    context.drawImage(bitmap, 0, 0, width, height);
    for (const quality of JPEG_QUALITIES) {
      const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, "image/jpeg", quality)
      );
      if (!blob)
        throw new Error("This browser could not make a JPEG of the photo");
      if (blob.size <= UNIT_PHOTO_MAX_BYTES) {
        const name = file.name.replace(/\.[^.]*$/, "") + ".jpg";
        return new File([blob], name, {
          type: "image/jpeg",
          lastModified: Date.now(),
        });
      }
    }
    throw new Error(
      "The photo is too detailed to store small enough. Try another photo."
    );
  } finally {
    bitmap.close();
  }
}
