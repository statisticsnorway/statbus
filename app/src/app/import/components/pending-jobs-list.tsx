"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Tables } from "@/lib/database.types";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { InfoIcon } from "lucide-react";

type ImportJob = Tables<"import_job">;

interface PendingJobsListProps {
  jobs: ImportJob[];
  onDeleteJob: (jobId: number) => Promise<void>;
  unitTypeTitle: string;
  unitTypeDescription: string;
  uploadPathPrefix: string;
}

const formatDate = (dateString: string | null) => {
  if (dateString === null || dateString === 'infinity') {
    return 'infinity';
  }
  if (!dateString) {
    return '';
  }
  try {
    const date = new Date(dateString);
    if (isNaN(date.getTime())) {
      console.warn(`formatDate: Invalid date string received: "${dateString}"`);
      return 'Invalid Date';
    }
    return date.toLocaleDateString('nb-NO', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
  } catch (e) {
    console.error(`Error formatting date string "${dateString}":`, e);
    return dateString; // Fallback
  }
};

export function PendingJobsList({ jobs, onDeleteJob, unitTypeTitle, unitTypeDescription, uploadPathPrefix }: PendingJobsListProps) {
  const router = useRouter();
  const [jobToDelete, setJobToDelete] = useState<number | null>(null);

  if (jobs.length === 0) {
    return null;
  }

  const handleConfirmDelete = () => {
    if (jobToDelete) {
      onDeleteJob(jobToDelete);
    }
    setJobToDelete(null);
  };

  return (
    <>
      <div className="bg-blue-50 border border-blue-200 rounded-md p-4 mb-6">
      <h3 className="font-medium mb-2">Pending Import Jobs</h3>
      <p className="text-sm mb-4">
        You have {jobs.length} pending {unitTypeDescription} import {jobs.length === 1 ? 'job' : 'jobs'} waiting for upload.
        Would you like to continue with one of these?
      </p>
      <div className="space-y-2">
        {jobs.map(job => (
          <div key={job.id} className="flex justify-between items-center bg-white p-3 rounded border">
            <div>
              <p className="font-medium">{unitTypeTitle}</p>
              <div className="text-xs text-gray-500 mt-1">
                {job.default_valid_from ? (
                  <p className="flex items-center space-x-1">
                    <span>Valid from {formatDate(job.default_valid_from)} to {formatDate(job.default_valid_to)}</span>
                    {(job.default_valid_to === null || job.default_valid_to === 'infinity') && (
                      <Dialog>
                        <DialogTrigger asChild>
                          <InfoIcon className="h-3.5 w-3.5 cursor-help text-gray-400" />
                        </DialogTrigger>
                        <DialogContent>
                          <DialogHeader>
                            <DialogTitle>What does &quot;infinity&quot; mean?</DialogTitle>
                          </DialogHeader>
                          <div className="py-4">
                            <p>Infinity means the data is valid until new information arrives. When new data is provided for an overlapping period, the new information will supersede the old, effectively ending the &quot;infinity&quot; period for the previous record.</p>
                          </div>
                          <DialogFooter>
                            <DialogClose asChild>
                              <Button type="button">OK</Button>
                            </DialogClose>
                          </DialogFooter>
                        </DialogContent>
                      </Dialog>
                    )}
                  </p>
                ) : (
                  <p>Valid from columns &quot;valid_from&quot; to &quot;valid_to&quot;</p>
                )}
              </div>
            </div>
            <div className="flex items-center space-x-2">
              <Button 
                size="sm"
                onClick={() => router.push(`${uploadPathPrefix}/${job.slug}`)}
              >
                Continue
              </Button>
              <Button
                variant="destructive"
                size="sm"
                onClick={() => setJobToDelete(job.id)}
              >
                Cancel
              </Button>
            </div>
          </div>
        ))}
      </div>
    </div>

    <AlertDialog open={jobToDelete !== null} onOpenChange={(open) => !open && setJobToDelete(null)}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Are you sure?</AlertDialogTitle>
          <AlertDialogDescription>
            This will permanently delete the import job. This action cannot be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel onClick={() => setJobToDelete(null)}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            onClick={handleConfirmDelete}
          >
            Confirm Delete
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </>
  );
}
