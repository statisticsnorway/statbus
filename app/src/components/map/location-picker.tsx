"use client";

import { useCallback, useRef, useState } from "react";
import type { Map as MapLibreMap, Marker } from "maplibre-gl";
import { MapPin } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { UnitMap, cssColour } from "./unit-map";
import { pickerStart, roundCoordinate } from "./map-data";

/**
 * "Pick on map" beside a physical location's latitude and longitude (z2qt08, owner
 * 2026-11-18): a map opens at the location's point, else its region's centre, else the
 * country; a click or a drag puts the pin, and "Use this point" writes latitude and
 * longitude into the form's inputs, where Save stores them as before. Altitude stays as it
 * is. Finding a place from the address is a geocoding workflow (nq8zqt), not done here.
 */
export function LocationPicker({
  formRef,
  regionCentre,
}: {
  /** The form holding the inputs named latitude and longitude. */
  formRef: React.RefObject<HTMLElement | null>;
  regionCentre: { latitude: number | null; longitude: number | null } | null;
}) {
  const [open, setOpen] = useState(false);
  const [point, setPoint] = useState<[number, number] | null>(null);
  // The point the pin starts on, set when the dialog opens.
  const pointRef = useRef<[number, number] | null>(null);
  const markerRef = useRef<Marker | null>(null);
  const startRef = useRef<{ center: [number, number]; zoom: number } | null>(null);

  const input = (name: string) => formRef.current?.querySelector<HTMLInputElement>(`input[name="${name}"]`) ?? null;

  const begin = () => {
    const start = pickerStart(input("latitude")?.value, input("longitude")?.value, regionCentre);
    startRef.current = { center: start.center, zoom: start.zoom };
    pointRef.current = start.fromLocation ? start.center : null;
    setPoint(pointRef.current);
    setOpen(true);
  };

  const onReady = useCallback((map: MapLibreMap) => {
    const start = startRef.current;
    // The dialog opens with a zoom animation, so the map measured its box mid-way; measure
    // again once it has settled, or markers are placed against the wrong size.
    const settle = () => {
      map.resize();
      if (start) map.jumpTo(start);
    };
    settle();
    window.setTimeout(settle, 250);
    import("maplibre-gl").then(({ Marker }) => {
      const marker = new Marker({ draggable: true, color: cssColour("--color-legal_unit-600") || undefined });
      markerRef.current = marker;
      const place = (lngLat: [number, number]) => {
        marker.setLngLat(lngLat).addTo(map);
        setPoint([roundCoordinate(lngLat[0]), roundCoordinate(lngLat[1])]);
      };
      // The stored point, if any, is where the map opened.
      if (start && pointRef.current) marker.setLngLat(pointRef.current).addTo(map);
      map.on("click", (e) => place([e.lngLat.lng, e.lngLat.lat]));
      marker.on("dragend", () => {
        const { lng, lat } = marker.getLngLat();
        place([lng, lat]);
      });
    });
  }, []);

  const use = () => {
    if (!point) return;
    setValue(input("longitude"), String(point[0]));
    setValue(input("latitude"), String(point[1]));
    setOpen(false);
  };

  return (
    <>
      <Button type="button" variant="outline" size="sm" onClick={begin} data-location-picker="">
        <MapPin className="mr-1.5 h-4 w-4" />
        Pick on map
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-3xl">
          <DialogHeader>
            <DialogTitle>Pick the location</DialogTitle>
            <DialogDescription>Click the map or drag the pin to the unit&apos;s place.</DialogDescription>
          </DialogHeader>
          <div className="relative h-[28rem] overflow-hidden rounded border">
            {open && <UnitMap onReady={onReady} className="absolute inset-0" />}
          </div>
          <DialogFooter className="items-center gap-3 sm:justify-between">
            <span className="text-sm tabular-nums text-gray-600" data-location-picker-point="">
              {point ? `Latitude ${point[1]}, longitude ${point[0]}` : "No point yet"}
            </span>
            <div className="flex gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="button" onClick={use} disabled={!point} data-location-picker-use="">
                Use this point
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

/**
 * Sets an input's value so React sees it as typed: the native setter, then an input event,
 * so the field's own state (FormField keeps one) and the form's Save both get the value.
 */
function setValue(el: HTMLInputElement | null, value: string) {
  if (!el) return;
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
  setter?.call(el, value);
  el.dispatchEvent(new Event("input", { bubbles: true }));
}
