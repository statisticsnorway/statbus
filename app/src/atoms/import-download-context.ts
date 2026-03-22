import { atom } from 'jotai';

export interface ImportDownloadContext {
  jobId: number;
  jobSlug: string;
  totalRows: number;
  errorCount: number;
  warningCount: number;
}

export const importDownloadContextAtom = atom<ImportDownloadContext | null>(null);
