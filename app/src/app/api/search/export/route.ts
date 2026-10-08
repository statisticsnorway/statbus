import { NextRequest, NextResponse } from "next/server";
import { openExportStream } from "@/app/search/export/export-copy-stream";
import {
  ExportQueryError,
  EXPORT_TOTAL_ROWS_HEADER,
} from "@/app/search/export/export-sql";
import { exportBaseName } from "@/app/search/export/export-query";
import { createServerLogger } from "@/lib/server-logger";
import { describeError } from "@/lib/error-format";

/**
 * GET /api/search/export?<search page filters>&order=...[&max_rows=N]
 *
 * The ONE statistical-unit export mechanism (STATBUS-421 Phase 2): a CSV
 * streamed straight from `COPY (SELECT ...) TO STDOUT WITH (FORMAT CSV,
 * HEADER)`, executed as the caller's own database role via
 * auth.jwt_switch_role on the `statbus` cookie, so RLS applies exactly as on
 * /rest. Both client formats consume it: CSV is written to disk as it
 * arrives, XLSX is converted from it in a browser Worker.
 *
 * Response headers:
 *   X-Export-Total-Rows  exact row count of THIS export (same snapshot as the
 *                        COPY); the client's completeness check compares the
 *                        records it received against it.
 * Errors before streaming are JSON: 400 unsupported filter, 401 no/invalid
 * token, 413 more rows than max_rows (the Excel refusal), 500 otherwise.
 * A failure after streaming has begun aborts the response (the client sees a
 * network error and a short row count) and is logged server-side with rows
 * sent, expected rows, bytes and elapsed time.
 */

export const dynamic = "force-dynamic";

function isAuthError(message: string): boolean {
  return /^(Invalid token|Token has expired|Token does not contain role claim|Role .* does not exist)/.test(
    message
  );
}

export async function GET(request: NextRequest) {
  const accessToken = request.cookies.get("statbus")?.value;
  if (!accessToken) {
    return NextResponse.json(
      { message: "Authentication required" },
      { status: 401 }
    );
  }

  const url = new URL(request.url);
  const params = new URLSearchParams(url.searchParams);
  const maxRowsParam = params.get("max_rows");
  params.delete("max_rows");
  let maxRows: number | null = null;
  if (maxRowsParam != null) {
    maxRows = Number(maxRowsParam);
    if (!Number.isSafeInteger(maxRows) || maxRows < 0) {
      return NextResponse.json(
        { message: "max_rows must be a non-negative integer" },
        { status: 400 }
      );
    }
  }

  // Created inside the request context (it reads request headers); used by
  // the stream callbacks after the response has started.
  const logger = await createServerLogger().catch(() => null);
  const logContext = { url: `${url.pathname}${url.search}` };

  let result;
  try {
    result = await openExportStream({
      accessToken,
      params,
      maxRows,
      onFailure: (failure) => {
        const context = { ...logContext, ...failure };
        console.error("Search export failed mid-stream", context);
        logger?.error(
          context,
          `Search export failed mid-stream: ${failure.error}`
        );
      },
      onSuccess: (success) => {
        const context = { ...logContext, ...success };
        console.info("Search export completed", context);
        logger?.info(
          context,
          `Search export completed: ${success.rowsSent} rows`
        );
      },
    });
  } catch (error) {
    const message = describeError(error);
    if (error instanceof ExportQueryError) {
      return NextResponse.json({ message }, { status: 400 });
    }
    if (isAuthError(message)) {
      return NextResponse.json({ message }, { status: 401 });
    }
    console.error("Search export could not start", {
      ...logContext,
      error: message,
    });
    logger?.error(
      { ...logContext, error: message },
      `Search export could not start: ${message}`
    );
    return NextResponse.json(
      { message: `Export failed: ${message}` },
      { status: 500 }
    );
  }

  if (result.kind === "too-many-rows") {
    return NextResponse.json(
      {
        message: `This export has ${result.totalRows} rows; at most ${result.maxRows} are allowed for this format. Use CSV instead.`,
        totalRows: result.totalRows,
        maxRows: result.maxRows,
      },
      {
        status: 413,
        headers: { [EXPORT_TOTAL_ROWS_HEADER]: String(result.totalRows) },
      }
    );
  }

  request.signal.addEventListener("abort", () => result.abort(), {
    once: true,
  });

  const filename = `${exportBaseName(params.get("unit_type"))}.csv`;
  return new Response(result.stream, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Cache-Control": "no-store",
      "X-Accel-Buffering": "no",
      [EXPORT_TOTAL_ROWS_HEADER]: String(result.totalRows),
      "Access-Control-Expose-Headers": EXPORT_TOTAL_ROWS_HEADER,
    },
  });
}
