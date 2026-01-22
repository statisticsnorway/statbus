"use client";

import * as React from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

interface ImageUploadProps {
  onFileSelect: (file: File) => void;
  maxSizeMB?: number;
  className?: string;
}

interface ImageInfo {
  file: File;
  url: string;
  width: number;
  height: number;
  sizeMB: number;
  needsResize: boolean;
}

export function ImageUpload({
  onFileSelect,
  maxSizeMB = 4,
  className,
}: ImageUploadProps) {
  const [imageInfo, setImageInfo] = React.useState<ImageInfo | null>(null);
  const [isResizing, setIsResizing] = React.useState(false);
  const fileInputRef = React.useRef<HTMLInputElement>(null);

  const loadImage = (file: File): Promise<HTMLImageElement> => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = URL.createObjectURL(file);
    });
  };

  const resizeImage = async (
    file: File,
    maxSizeMB: number
  ): Promise<File> => {
    const img = await loadImage(file);
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");

    if (!ctx) {
      throw new Error("Failed to get canvas context");
    }

    // Start with original dimensions
    let { width, height } = img;
    let quality = 0.9;
    let scaleFactor = 1;

    // Calculate initial scale factor to reduce very large images
    const maxDimension = 2048;
    if (width > maxDimension || height > maxDimension) {
      scaleFactor = maxDimension / Math.max(width, height);
      width = Math.round(width * scaleFactor);
      height = Math.round(height * scaleFactor);
    }

    // Iteratively reduce quality/size until under maxSizeMB
    let blob: Blob | null = null;
    let attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      canvas.width = width;
      canvas.height = height;

      // Draw image with current dimensions
      ctx.clearRect(0, 0, width, height);
      ctx.drawImage(img, 0, 0, width, height);

      // Convert to blob
      blob = await new Promise<Blob | null>((resolve) => {
        canvas.toBlob(resolve, file.type || "image/jpeg", quality);
      });

      if (!blob) {
        throw new Error("Failed to create blob");
      }

      const sizeMB = blob.size / (1024 * 1024);

      if (sizeMB <= maxSizeMB) {
        break;
      }

      // Reduce quality or dimensions
      if (quality > 0.5) {
        quality -= 0.1;
      } else {
        scaleFactor *= 0.9;
        width = Math.round(img.width * scaleFactor);
        height = Math.round(img.height * scaleFactor);
        quality = 0.9; // Reset quality when reducing dimensions
      }

      attempts++;
    }

    if (!blob) {
      throw new Error("Failed to resize image");
    }

    // Create new File from blob
    const resizedFile = new File([blob], file.name, {
      type: file.type || "image/jpeg",
      lastModified: Date.now(),
    });

    return resizedFile;
  };

  const handleFileChange = async (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = event.target.files?.[0];
    if (!file) return;

    try {
      const img = await loadImage(file);
      const sizeMB = file.size / (1024 * 1024);
      const needsResize = sizeMB > maxSizeMB;

      setImageInfo({
        file,
        url: img.src,
        width: img.naturalWidth,
        height: img.naturalHeight,
        sizeMB,
        needsResize,
      });

      // If doesn't need resize, immediately call onFileSelect
      if (!needsResize) {
        onFileSelect(file);
      }
    } catch (error) {
      console.error("Failed to load image:", error);
      alert("Failed to load image. Please try another file.");
    }
  };

  const handleResize = async () => {
    if (!imageInfo) return;

    setIsResizing(true);
    try {
      const resizedFile = await resizeImage(imageInfo.file, maxSizeMB);
      const img = await loadImage(resizedFile);
      const sizeMB = resizedFile.size / (1024 * 1024);

      setImageInfo({
        file: resizedFile,
        url: img.src,
        width: img.naturalWidth,
        height: img.naturalHeight,
        sizeMB,
        needsResize: false,
      });

      onFileSelect(resizedFile);
    } catch (error) {
      console.error("Failed to resize image:", error);
      alert("Failed to resize image. Please try another file.");
    } finally {
      setIsResizing(false);
    }
  };

  const handleUseOriginal = () => {
    if (!imageInfo) return;
    onFileSelect(imageInfo.file);
  };

  const handleReset = () => {
    setImageInfo(null);
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  };

  React.useEffect(() => {
    // Cleanup object URLs on unmount
    return () => {
      if (imageInfo?.url) {
        URL.revokeObjectURL(imageInfo.url);
      }
    };
  }, [imageInfo?.url]);

  return (
    <div className={cn("space-y-4", className)}>
      <div className="flex items-center gap-2">
        <Input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          onChange={handleFileChange}
          className="flex-1"
        />
        {imageInfo && (
          <Button variant="outline" size="sm" onClick={handleReset}>
            Clear
          </Button>
        )}
      </div>

      {imageInfo && (
        <div className="space-y-4 rounded-lg border border-zinc-200 p-4 dark:border-zinc-800">
          {/* Preview */}
          <div className="flex justify-center">
            <img
              src={imageInfo.url}
              alt="Preview"
              className="max-h-64 rounded-md border border-zinc-200 object-contain dark:border-zinc-800"
            />
          </div>

          {/* Image Info */}
          <div className="space-y-1 text-sm text-zinc-600 dark:text-zinc-400">
            <div className="flex justify-between">
              <span>Dimensions:</span>
              <span className="font-medium text-zinc-900 dark:text-zinc-50">
                {imageInfo.width} × {imageInfo.height}
              </span>
            </div>
            <div className="flex justify-between">
              <span>Size:</span>
              <span
                className={cn(
                  "font-medium",
                  imageInfo.needsResize
                    ? "text-red-600 dark:text-red-400"
                    : "text-zinc-900 dark:text-zinc-50"
                )}
              >
                {imageInfo.sizeMB.toFixed(2)} MB
              </span>
            </div>
          </div>

          {/* Warning and Actions */}
          {imageInfo.needsResize && (
            <div className="space-y-3 rounded-md border border-amber-200 bg-amber-50 p-3 dark:border-amber-900/50 dark:bg-amber-950/20">
              <p className="text-sm text-amber-900 dark:text-amber-200">
                Image exceeds {maxSizeMB} MB limit. You can resize it to fit or
                use the original.
              </p>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  onClick={handleResize}
                  disabled={isResizing}
                >
                  {isResizing ? "Resizing..." : "Resize Image"}
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={handleUseOriginal}
                >
                  Use Original
                </Button>
              </div>
            </div>
          )}

          {!imageInfo.needsResize && (
            <div className="rounded-md border border-green-200 bg-green-50 p-3 dark:border-green-900/50 dark:bg-green-950/20">
              <p className="text-sm text-green-900 dark:text-green-200">
                Image ready for upload ({imageInfo.sizeMB.toFixed(2)} MB)
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
