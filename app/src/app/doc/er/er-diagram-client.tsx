"use client";

import { useEffect, useState } from "react";
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
          className="mermaid-container overflow-auto"
          dangerouslySetInnerHTML={{ __html: svg }}
        />
      )}
      <style jsx>{`
        .mermaid-container :global(svg) {
          max-width: none !important;
        }
      `}</style>
    </div>
  );
}
