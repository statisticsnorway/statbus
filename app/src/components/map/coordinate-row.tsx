"use client";

import { useRef } from "react";
import { LocationPicker } from "./location-picker";

/**
 * The latitude, longitude and altitude row of a physical location form, with "Pick on map"
 * above it while the location is being edited (z2qt08). The picker finds the row's inputs by
 * name and opens at the region's centre when the location has no point yet.
 */
export function CoordinateRow({
  isEditing,
  regionCentre,
  children,
}: {
  isEditing: boolean;
  regionCentre: { latitude: number | null; longitude: number | null } | null;
  children: React.ReactNode;
}) {
  const rowRef = useRef<HTMLDivElement>(null);
  return (
    <div ref={rowRef} className="space-y-2" data-coordinate-row="">
      {isEditing && (
        <div className="flex justify-end">
          <LocationPicker formRef={rowRef} regionCentre={regionCentre} />
        </div>
      )}
      <div className="grid lg:grid-cols-3 gap-4">{children}</div>
    </div>
  );
}
