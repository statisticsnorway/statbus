"use client";

import * as React from "react";
import { cn } from "@/lib/utils";
import { Input } from "@/components/ui/input";
import { toUnitPhoto, UNIT_PHOTO_PIXELS } from "@/lib/unit-photo";

// Validate file MIME type before creating blob URL for preview
// Defense-in-depth: server also validates magic bytes, but this prevents
// creating blob URLs for obviously non-image files (CodeQL js/xss-through-dom)
const ALLOWED_IMAGE_TYPES = [
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
];

const isValidImageFile = (file: File): boolean =>
  ALLOWED_IMAGE_TYPES.includes(file.type);

interface ImageUploadProps {
  onFileSelect: (file: File) => void;
  className?: string;
}

/**
 * Picks a photo and turns it into a unit photo: the centred square, scaled to
 * UNIT_PHOTO_PIXELS, as JPEG (see @/lib/unit-photo). The field around it shows
 * the photo; this states its stored size.
 */
export function ImageUpload({ onFileSelect, className }: ImageUploadProps) {
  const [preview, setPreview] = React.useState<{ kb: number } | null>(null);
  const [problem, setProblem] = React.useState<string | null>(null);
  const fileInputRef = React.useRef<HTMLInputElement>(null);

  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setProblem(null);

    if (!isValidImageFile(file)) {
      setProblem("Choose a PNG, JPEG, GIF or WebP photo. SVG files are not supported.");
      if (fileInputRef.current) fileInputRef.current.value = "";
      return;
    }

    try {
      const photo = await toUnitPhoto(file);
      setPreview({ kb: Math.ceil(photo.size / 1024) });
      onFileSelect(photo);
    } catch (error) {
      setProblem(error instanceof Error ? error.message : "The photo could not be read. Try another file.");
    }
  };

  return (
    <div className={cn("space-y-2", className)}>
      <Input
        ref={fileInputRef}
        type="file"
        accept=".png,.jpg,.jpeg,.gif,.webp,image/png,image/jpeg,image/gif,image/webp"
        onChange={handleFileChange}
      />
      {preview && (
        <p className="text-sm text-zinc-600">
          Square, {UNIT_PHOTO_PIXELS} × {UNIT_PHOTO_PIXELS}, {preview.kb} KB
        </p>
      )}
      {problem && <p className="text-sm text-red-600">{problem}</p>}
    </div>
  );
}
