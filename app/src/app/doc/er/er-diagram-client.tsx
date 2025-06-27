"use client";

import { useEffect, useState, useRef } from "react";
import mermaid from "mermaid";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Spinner } from "@/components/ui/spinner";

mermaid.initialize({
  startOnLoad: false,
});

export default function ErDiagramClientComponent() {
  const [svg, setSvg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const containerRef = useRef<HTMLDivElement>(null);
  const panZoomInstanceRef = useRef<SvgPanZoom.Instance | null>(null);

  useEffect(() => {
    const fetchAndRenderDiagram = async () => {
      setLoading(true);
      setError(null);
      try {
        const client = await getBrowserRestClient();
        const { data: diagramText, error: fetchError } = await client
          .rpc("generate_mermaid_er_diagram")
          .single();

        if (fetchError) {
          throw fetchError;
        }

        if (!diagramText) {
          throw new Error("No diagram data received.");
        }

        const fullDiagramText = `---
config:
    layout: elk
---
${diagramText}`;
        const { svg: renderedSvg } = await mermaid.render(
          "er-diagram-graph",
          fullDiagramText,
        );
        setSvg(renderedSvg);
        setError(null);
      } catch (e: any) {
        console.error("Fetching or rendering error:", e);
        setError(e.message || "Failed to load or render diagram");
        setSvg(null);
      } finally {
        setLoading(false);
      }
    };

    fetchAndRenderDiagram();
  }, []);

  useEffect(() => {
    const container = containerRef.current;
    if (svg && container) {
      const svgElement = container.querySelector("svg");
      if (svgElement && !panZoomInstanceRef.current) {
        // Ensure the SVG fills the container before initialization to avoid clipping
        svgElement.style.width = "100%";
        svgElement.style.height = "100%";

        import("svg-pan-zoom").then(({ default: svgPanZoom }) => {
          // Check if component is still mounted and instance not created
          if (containerRef.current && !panZoomInstanceRef.current) {
            panZoomInstanceRef.current = svgPanZoom(svgElement, {
              zoomEnabled: true,
              controlIconsEnabled: true,
              fit: true,
              center: true,
              minZoom: 0.3,
              maxZoom: 10,
            });
          }
        });
      }
    }

    return () => {
      if (panZoomInstanceRef.current) {
        panZoomInstanceRef.current.destroy();
        panZoomInstanceRef.current = null;
      }
    };
  }, [svg]);

  return (
    <div className="mt-4">
      {loading && (
        <Spinner message="Loading and rendering diagram, this may take a moment..." />
      )}
      {error && (
        <div
          className="relative rounded border border-red-400 bg-red-100 px-4 py-3 text-red-700"
          role="alert"
        >
          <strong className="font-bold">Error:</strong>
          <span className="ml-2 block sm:inline">{error}</span>
        </div>
      )}
      {svg && (
        <div
          ref={containerRef}
          className="mermaid-container"
          dangerouslySetInnerHTML={{ __html: svg }}
        />
      )}
      <style jsx>{`
        .mermaid-container {
          width: 100%;
          height: 80vh;
          overflow: hidden;
          border: 1px solid #ccc;
        }
        .mermaid-container :global(svg) {
          max-width: none !important;
          cursor: grab;
        }
        .mermaid-container :global(svg:active) {
          cursor: grabbing;
        }
        .mermaid-container :global(.svg-pan-zoom-control) {
          cursor: pointer;
        }
      `}</style>
    </div>
  );
}
