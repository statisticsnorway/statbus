/**
 * The base map every StatBus map draws on (owner 2026-11-22, z2qt08): OpenFreeMap's public
 * vector tiles, no key, light use. Serving tiles from the installation itself is a9168x; it
 * changes this file only.
 */
export const BASEMAP_STYLE_URL =
  "https://tiles.openfreemap.org/styles/positron";

/**
 * The only font family OpenFreeMap's glyph server has. A symbol layer that names no font asks
 * for MapLibre's default ("Open Sans Regular, Arial Unicode MS Regular"), which answers 404
 * there and stops the layer from drawing, so every text layer names this one.
 */
export const BASEMAP_FONT = ["Noto Sans Regular"];
/** The bold face of the same family (Noto Sans Bold), on the same glyph server. */
export const BASEMAP_FONT_BOLD = ["Noto Sans Bold"];

/**
 * The base map's border layers (country, county and smaller, disputed), hidden on every StatBus
 * map (team feedback 2026-11-26, z2qt08): a registry's map places units and regions, and drawing
 * borders takes a side where they are disputed. Coastlines, water and place names stay.
 */
export const BASEMAP_BORDER_LAYERS = [
  "boundary_2",
  "boundary_3",
  "boundary_disputed",
];
