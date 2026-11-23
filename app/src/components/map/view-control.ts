import type { IControl, Map as MapLibreMap } from "maplibre-gl";

/**
 * Buttons stacked under the zoom buttons, in MapLibre's own control style, e.g. "fit all" and
 * "centre on the selected region" on the Regions map (owner 2026-11-23, z2qt08).
 */
export class ViewControl implements IControl {
  private container: HTMLDivElement | null = null;

  constructor(private readonly buttons: { title: string; icon: string; onClick: () => void }[]) {}

  onAdd(_map: MapLibreMap): HTMLElement {
    const container = document.createElement("div");
    container.className = "maplibregl-ctrl maplibregl-ctrl-group";
    for (const b of this.buttons) {
      const button = document.createElement("button");
      button.type = "button";
      button.title = b.title;
      button.setAttribute("aria-label", b.title);
      button.textContent = b.icon;
      button.style.fontSize = "16px";
      button.addEventListener("click", b.onClick);
      container.appendChild(button);
    }
    this.container = container;
    return container;
  }

  onRemove(): void {
    this.container?.remove();
    this.container = null;
  }
}
