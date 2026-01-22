"use client";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { X } from "lucide-react";

interface UnitImageProps {
  imageId: number | null | undefined;
  unitType: "establishment" | "legal_unit" | "enterprise";
  className?: string;
  onDelete?: () => void;
  isEditing?: boolean;
}

export function UnitImage({ 
  imageId, 
  unitType, 
  className, 
  onDelete, 
  isEditing = false 
}: UnitImageProps) {
  const [imageError, setImageError] = useState(false);
  const [imageLoading, setImageLoading] = useState(true);

  // Don't render anything if no imageId or if image failed to load
  if (!imageId || imageError) {
    return null;
  }

  return (
    <div className={cn("relative overflow-hidden rounded-lg bg-gray-100", className)}>
      {imageLoading && (
        <div className="absolute inset-0 flex items-center justify-center bg-gray-100">
          <div className="h-4 w-4 animate-pulse rounded-full bg-gray-300" />
        </div>
      )}
      <img
        src={`/rest/rpc/image_data?id=${imageId}`}
        alt={`${unitType} image`}
        className={cn(
          "h-full w-full object-cover rounded-lg transition-opacity",
          imageLoading ? "opacity-0" : "opacity-100"
        )}
        onLoad={() => setImageLoading(false)}
        onError={() => {
          setImageError(true);
          setImageLoading(false);
        }}
      />
      {isEditing && onDelete && !imageLoading && (
        <Button
          type="button"
          variant="destructive"
          size="icon"
          className="absolute top-1 right-1 h-6 w-6 rounded-full opacity-90 hover:opacity-100"
          onClick={onDelete}
          title="Delete image"
        >
          <X className="h-4 w-4" />
        </Button>
      )}
    </div>
  );
}
