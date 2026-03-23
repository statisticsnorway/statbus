"use client";

import { useState, useCallback, useRef } from "react";

export interface DownloadProgress {
  phase: 'idle' | 'downloading' | 'complete' | 'error';
  bytesReceived: number;
  elapsedMs: number;
  error?: string;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatElapsed(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

export function formatDownloadProgress(progress: DownloadProgress): string {
  if (progress.phase === 'downloading') {
    return `Downloading... ${formatBytes(progress.bytesReceived)} (${formatElapsed(progress.elapsedMs)})`;
  }
  if (progress.phase === 'complete') {
    return `Downloaded ${formatBytes(progress.bytesReceived)} in ${formatElapsed(progress.elapsedMs)}`;
  }
  if (progress.phase === 'error') {
    return progress.error || 'Download failed';
  }
  return '';
}

/**
 * Hook for downloading files with progress tracking and cancellation.
 * Uses fetch + ReadableStream to track bytes received.
 */
export function useProgressDownload() {
  const [progress, setProgress] = useState<DownloadProgress>({
    phase: 'idle', bytesReceived: 0, elapsedMs: 0,
  });
  const abortRef = useRef<AbortController | null>(null);

  const startDownload = useCallback(async (url: string, suggestedFilename?: string) => {
    // Cancel any in-progress download
    abortRef.current?.abort();

    const controller = new AbortController();
    abortRef.current = controller;
    const startTime = Date.now();

    setProgress({ phase: 'downloading', bytesReceived: 0, elapsedMs: 0 });

    try {
      const response = await fetch(url, { signal: controller.signal });

      if (!response.ok) {
        const text = await response.text();
        let message: string;
        try {
          message = JSON.parse(text).message || `Download failed (${response.status})`;
        } catch {
          message = `Download failed (${response.status})`;
        }
        setProgress({ phase: 'error', bytesReceived: 0, elapsedMs: Date.now() - startTime, error: message });
        return;
      }

      // Extract filename from Content-Disposition header
      const disposition = response.headers.get('Content-Disposition');
      const filenameMatch = disposition?.match(/filename="?([^";\n]+)"?/);
      const filename = filenameMatch?.[1] || suggestedFilename || 'download';

      // Stream the response body to track progress
      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('Response body is not readable');
      }

      const chunks: Uint8Array[] = [];
      let bytesReceived = 0;

      // Update progress every 100ms at most to avoid excessive re-renders
      let lastUpdate = 0;
      const UPDATE_INTERVAL = 100;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        chunks.push(value);
        bytesReceived += value.length;

        const now = Date.now();
        if (now - lastUpdate > UPDATE_INTERVAL) {
          lastUpdate = now;
          setProgress({
            phase: 'downloading',
            bytesReceived,
            elapsedMs: now - startTime,
          });
        }
      }

      // Assemble blob and trigger browser download
      const contentType = response.headers.get('Content-Type') || 'application/octet-stream';
      const blob = new Blob(chunks as BlobPart[], { type: contentType });
      const blobUrl = URL.createObjectURL(blob);

      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);

      setProgress({
        phase: 'complete',
        bytesReceived,
        elapsedMs: Date.now() - startTime,
      });

      // Auto-reset after 3 seconds
      setTimeout(() => {
        setProgress(prev => prev.phase === 'complete' ? { phase: 'idle', bytesReceived: 0, elapsedMs: 0 } : prev);
      }, 3000);

    } catch (err) {
      if (controller.signal.aborted) return; // cancelled, don't update state
      setProgress({
        phase: 'error',
        bytesReceived: 0,
        elapsedMs: Date.now() - startTime,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, []);

  const cancelDownload = useCallback(() => {
    abortRef.current?.abort();
    setProgress({ phase: 'idle', bytesReceived: 0, elapsedMs: 0 });
  }, []);

  return { progress, startDownload, cancelDownload };
}
