"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useSetAtom } from "jotai";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { usePermission } from "@/atoms/auth";
import { createImportJobFromDefinitionAtom } from "@/atoms/import";
import { deleteDefinitionAtom } from "@/atoms/definition-editor";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { getUploadPath } from "@/lib/import-mode-paths";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Spinner } from "@/components/ui/spinner";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Plus, Pencil, Trash2, Play } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import type { Tables } from "@/lib/database.types";
import { MODE_LABELS } from "./components/labels";

export default function DefinitionsPage() {
  const router = useRouter();
  const { canAccessAdminTools } = usePermission();
  const doCreateJob = useSetAtom(createImportJobFromDefinitionAtom);
  const doDelete = useSetAtom(deleteDefinitionAtom);

  const [definitions, setDefinitions] = useState<Tables<"import_definition">[]>([]);
  const [loading, setLoading] = useState(true);
  const [creatingJobFor, setCreatingJobFor] = useState<number | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);

  const loadDefinitions = async () => {
    try {
      const client = await getBrowserRestClient();
      const { data, error } = await client
        .from("import_definition")
        .select("*")
        .eq("enabled", true)
        .order("mode")
        .order("name");
      if (error) throw error;
      setDefinitions(data ?? []);
    } catch (err) {
      toast({
        title: `Failed to load definitions: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  useGuardedEffect(() => {
    if (canAccessAdminTools) loadDefinitions();
  }, [canAccessAdminTools], "DefinitionsPage:loadDefinitions");

  if (!canAccessAdminTools) {
    return (
      <div className="text-center py-12 text-muted-foreground">
        You do not have permission to manage import definitions.
      </div>
    );
  }

  const handleCreateJob = async (def: Tables<"import_definition">) => {
    setCreatingJobFor(def.id);
    try {
      const job = await doCreateJob({
        definitionId: def.id,
        description: `Job from ${def.name}`,
        timeContextIdent: null,
        defaultValidFrom: null,
        defaultValidTo: null,
        review: null,
      });
      toast({ title: `Created import job ${job.slug}` });
      router.push(getUploadPath(def.mode, job.slug));
    } catch (err) {
      toast({
        title: `Failed to create job: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    } finally {
      setCreatingJobFor(null);
    }
  };

  const handleDelete = async (def: Tables<"import_definition">) => {
    if (!confirm(`Delete definition "${def.name}"? This cannot be undone.`)) return;
    setDeletingId(def.id);
    try {
      await doDelete(def.id);
      toast({ title: `Deleted definition "${def.name}"` });
      loadDefinitions();
    } catch (err) {
      toast({
        title: `Failed to delete: ${err instanceof Error ? err.message : String(err)}`,
        variant: "destructive",
      });
    } finally {
      setDeletingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Import Definitions</h1>
        <Button onClick={() => router.push("/import/definitions/new")}>
          <Plus className="mr-2 h-4 w-4" />
          Create New Definition
        </Button>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-12">
          <Spinner className="h-6 w-6" />
        </div>
      ) : definitions.length === 0 ? (
        <p className="text-muted-foreground text-center py-8">No import definitions found.</p>
      ) : (
        <TooltipProvider>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Mode</TableHead>
                <TableHead>Strategy</TableHead>
                <TableHead>Valid Time</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {definitions.map((def) => (
                <TableRow key={def.id}>
                  <TableCell className="font-medium">
                    {def.custom ? (
                      <button
                        type="button"
                        className="hover:underline text-left"
                        onClick={() => router.push(`/import/definitions/${def.slug}/edit`)}
                      >
                        {def.name}
                      </button>
                    ) : (
                      def.name
                    )}
                  </TableCell>
                  <TableCell>{MODE_LABELS[def.mode] ?? def.mode}</TableCell>
                  <TableCell className="text-sm">{def.strategy.replace(/_/g, " ")}</TableCell>
                  <TableCell className="text-sm">{def.valid_time_from.replace(/_/g, " ")}</TableCell>
                  <TableCell>
                    {def.custom ? (
                      <Badge variant="outline">Custom</Badge>
                    ) : (
                      <Badge variant="secondary">System</Badge>
                    )}
                  </TableCell>
                  <TableCell>
                    {def.valid ? (
                      <Badge className="bg-green-100 text-green-800 hover:bg-green-100">Valid</Badge>
                    ) : (
                      <Tooltip>
                        <TooltipTrigger>
                          <Badge variant="destructive">Invalid</Badge>
                        </TooltipTrigger>
                        <TooltipContent className="max-w-xs">
                          {def.validation_error || "Unknown validation error"}
                        </TooltipContent>
                      </Tooltip>
                    )}
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex items-center justify-end gap-1">
                      {def.valid && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => handleCreateJob(def)}
                          disabled={creatingJobFor === def.id}
                          title="Create job"
                        >
                          {creatingJobFor === def.id ? (
                            <Spinner className="h-4 w-4" />
                          ) : (
                            <Play className="h-4 w-4" />
                          )}
                        </Button>
                      )}
                      {def.custom && (
                        <>
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => router.push(`/import/definitions/${def.slug}/edit`)}
                            title="Edit"
                          >
                            <Pencil className="h-4 w-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => handleDelete(def)}
                            disabled={deletingId === def.id}
                            title="Delete"
                          >
                            {deletingId === def.id ? (
                              <Spinner className="h-4 w-4" />
                            ) : (
                              <Trash2 className="h-4 w-4 text-destructive" />
                            )}
                          </Button>
                        </>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TooltipProvider>
      )}
    </div>
  );
}
