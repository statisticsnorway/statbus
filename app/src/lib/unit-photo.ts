/**
 * A unit's photo is how a field worker recognises a unit on the next visit: a shop
 * front, a sign. It is stored small, as a square JPEG of UNIT_PHOTO_PIXELS a side, so
 * a few photos per unit never weigh on the database. The database refuses anything
 * over 256 KB (public.image image_size_limit) and deletes a photo no unit shows any
 * more (public.image_drop_unreferenced).
 */
export const UNIT_PHOTO_PIXELS = 512;

/** JPEG quality for stored photos: a 512 px photo lands around 30-80 KB. */
export const UNIT_PHOTO_QUALITY = 0.85;

/** The largest centred square of a width x height picture, in source pixels. */
export function centreSquareCrop(width: number, height: number) {
  const side = Math.min(width, height);
  return {
    sx: Math.round((width - side) / 2),
    sy: Math.round((height - side) / 2),
    side,
  };
}

/**
 * Crops a picture the user chose to its centred square and scales it to
 * UNIT_PHOTO_PIXELS, as a JPEG file ready to upload. Runs in the browser.
 */
export async function toUnitPhoto(file: File): Promise<File> {
  const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  try {
    const { sx, sy, side } = centreSquareCrop(bitmap.width, bitmap.height);
    const target = Math.min(UNIT_PHOTO_PIXELS, side);
    const canvas = document.createElement("canvas");
    canvas.width = target;
    canvas.height = target;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("This browser cannot draw the photo");
    context.drawImage(bitmap, sx, sy, side, side, 0, 0, target, target);
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", UNIT_PHOTO_QUALITY)
    );
    if (!blob) throw new Error("This browser could not make a JPEG of the photo");
    const name = file.name.replace(/\.[^.]*$/, "") + ".jpg";
    return new File([blob], name, { type: "image/jpeg", lastModified: Date.now() });
  } finally {
    bitmap.close();
  }
}
