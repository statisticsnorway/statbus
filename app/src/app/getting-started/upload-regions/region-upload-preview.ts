/**
 * What a region file would do before it is stored (owner 2026-11-26, 5yxn4w): the upload shows it,
 * and only a confirmed file is sent. It follows the rule admin.region_upload_upsert applies, so the
 * preview and the stored result agree (test/sql/414): a row changes only what it gives; a new
 * region needs a name; latitude and longitude come as a pair; an altitude needs a point.
 */

/** A region as the region_upload view returns it. */
export interface StoredRegion {
  path: string | null;
  name: string | null;
  latitude: string | number | null;
  longitude: string | number | null;
  altitude: string | number | null;
}

export interface RegionChange {
  /** The file line the row is on (1-based, the header is line 1). */
  line: number;
  path: string;
  name: string;
  /** For a changed name, the stored one. */
  oldName?: string;
}

export interface RegionUploadError {
  line: number;
  message: string;
}

export interface RegionUploadPreview {
  rows: number;
  added: RegionChange[];
  renamed: RegionChange[];
  coordinatesSet: RegionChange[];
  coordinatesMoved: RegionChange[];
  unchanged: number;
  /** Stored regions the file does not name: they stay as they are. */
  notInFile: number;
  errors: RegionUploadError[];
}

const COLUMNS = ["path", "name", "latitude", "longitude", "altitude"] as const;

const PATH = /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/;

function number(text: string): number | null {
  if (text.trim() === "") return null;
  const n = Number(text.trim());
  return Number.isFinite(n) ? n : NaN;
}

function same(a: number | null, b: string | number | null): boolean {
  const other = b === null || b === "" ? null : Number(b);
  return a === other || (a !== null && other !== null && Math.abs(a - other) < 5e-7);
}

/**
 * The preview of a parsed file (`header` and data `rows`, each row with its file line) against the
 * regions stored now.
 */
export function previewRegionUpload(
  header: string[],
  rows: { fields: string[]; line: number }[],
  stored: StoredRegion[]
): RegionUploadPreview {
  const preview: RegionUploadPreview = {
    rows: rows.length,
    added: [],
    renamed: [],
    coordinatesSet: [],
    coordinatesMoved: [],
    unchanged: 0,
    notInFile: 0,
    errors: [],
  };
  const columns = header.map((h) => h.trim());
  const unknown = columns.filter((c) => !(COLUMNS as readonly string[]).includes(c));
  if (unknown.length > 0) {
    preview.errors.push({
      line: 1,
      message: `Unknown column${unknown.length > 1 ? "s" : ""} ${unknown.join(", ")}. The columns are ${COLUMNS.join(", ")}.`,
    });
  }
  if (!columns.includes("path")) {
    preview.errors.push({ line: 1, message: "The file has no path column, which names each region." });
    return preview;
  }
  const at = (row: string[], column: (typeof COLUMNS)[number]) => {
    const i = columns.indexOf(column);
    return i < 0 ? "" : (row[i] ?? "").trim();
  };

  const byPath = new Map(stored.filter((r) => r.path).map((r) => [r.path as string, r]));
  const known = new Set(byPath.keys());
  const seen = new Set<string>();

  for (const { fields, line } of rows) {
    const path = at(fields, "path");
    const name = at(fields, "name");
    const fail = (message: string) => preview.errors.push({ line, message: `${path || "(no path)"}: ${message}` });
    if (!path) {
      fail("the path is empty");
      continue;
    }
    if (!PATH.test(path)) {
      fail("a path is codes separated by dots, like 46 or 46.4601");
      continue;
    }
    if (seen.has(path)) {
      fail("the path is in the file twice");
      continue;
    }
    seen.add(path);
    const parent = path.includes(".") ? path.slice(0, path.lastIndexOf(".")) : null;
    if (parent && !known.has(parent)) {
      fail(`its parent ${parent} is not in the region list, nor above it in the file`);
      continue;
    }

    const latitude = number(at(fields, "latitude"));
    const longitude = number(at(fields, "longitude"));
    const altitude = number(at(fields, "altitude"));
    if (Number.isNaN(latitude) || Number.isNaN(longitude) || Number.isNaN(altitude)) {
      fail("a coordinate is not a number (use a dot for decimals)");
      continue;
    }
    if ((latitude === null) !== (longitude === null)) {
      fail("latitude and longitude go together; give both or neither");
      continue;
    }
    if (latitude !== null && (latitude < -90 || latitude > 90)) {
      fail(`latitude ${latitude} is outside -90 to 90`);
      continue;
    }
    if (longitude !== null && (longitude < -180 || longitude > 180)) {
      fail(`longitude ${longitude} is outside -180 to 180`);
      continue;
    }
    if (altitude !== null && altitude < 0) {
      fail(`altitude ${altitude} is below zero`);
      continue;
    }

    const current = byPath.get(path);
    if (!current) {
      if (!name) {
        fail("a new region needs a name");
        continue;
      }
      if (altitude !== null && latitude === null) {
        fail("an altitude needs latitude and longitude");
        continue;
      }
      known.add(path);
      preview.added.push({ line, path, name });
      if (latitude !== null) preview.coordinatesSet.push({ line, path, name });
      continue;
    }

    const hasPoint = current.latitude !== null && current.latitude !== "";
    if (altitude !== null && latitude === null && !hasPoint) {
      fail("an altitude needs latitude and longitude, and the region has none");
      continue;
    }
    let changed = false;
    if (name && name !== current.name) {
      preview.renamed.push({ line, path, name, oldName: current.name ?? "" });
      changed = true;
    }
    const shown = name || current.name || path;
    if (latitude !== null) {
      const moved = !same(latitude, current.latitude) || !same(longitude, current.longitude);
      if (!hasPoint) {
        preview.coordinatesSet.push({ line, path, name: shown });
        changed = true;
      } else if (moved || (altitude !== null && !same(altitude, current.altitude))) {
        preview.coordinatesMoved.push({ line, path, name: shown });
        changed = true;
      }
    } else if (altitude !== null && !same(altitude, current.altitude)) {
      preview.coordinatesMoved.push({ line, path, name: shown });
      changed = true;
    }
    if (!changed) preview.unchanged++;
  }
  preview.notInFile = [...byPath.keys()].filter((p) => !seen.has(p)).length;
  return preview;
}
