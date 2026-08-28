"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Trash2, Undo2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
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
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";

/**
 * Delete / Restore for one user row (STATBUS-309).
 *
 * The rules are NOT here. `user_delete` is SECURITY INVOKER, so RLS decides who
 * may act and database triggers decide which transitions are legal. This
 * component's only jobs are to ask for confirmation by name and to show what
 * the database said.
 *
 * Errors are surfaced VERBATIM. The trigger messages are already written for
 * the person reading them — "Admins cannot remove themselves (x@y)", "Cannot
 * remove the last active admin user (x@y)" — and each carries a HINT naming the
 * way forward. Rewording them here would lose that and risk describing a rule
 * this component does not own.
 */
export function UserDeleteAction({
  user,
  onChanged,
}: {
  readonly user: Tables<"user">;
  readonly onChanged: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isDeleted = user.deleted_at !== null;
  const label = user.display_name ?? user.email ?? `user ${user.id}`;

  const run = async () => {
    if (user.id === null) return;
    setBusy(true);
    setError(null);
    try {
      const client = await getBrowserRestClient();
      const { error: rpcError } = isDeleted
        ? await client.rpc("user_restore", { p_user_id: user.id })
        : await client.rpc("user_delete", { p_user_id: user.id });

      if (rpcError) {
        // Verbatim, hint included when PostgREST supplies one.
        setError(rpcError.hint ? `${rpcError.message} — ${rpcError.hint}` : rpcError.message);
        return;
      }
      setConfirming(false);
      onChanged();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      {isDeleted && (
        <Badge variant="secondary" className="mr-2 align-middle">
          Deleted
        </Badge>
      )}
      <Button
        variant="ghost"
        className="inline-block"
        title={isDeleted ? `Restore ${label}` : `Delete ${label}`}
        onClick={() => {
          setError(null);
          setConfirming(true);
        }}
      >
        {isDeleted ? (
          <Undo2 className="w-4 h-4" />
        ) : (
          <Trash2 className="w-4 h-4" />
        )}
      </Button>

      <AlertDialog open={confirming} onOpenChange={setConfirming}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {isDeleted ? "Restore this user?" : "Delete this user?"}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {isDeleted ? (
                <>
                  <strong>{label}</strong> will be able to sign in again.
                </>
              ) : (
                <>
                  <strong>{label}</strong> will no longer be able to sign in,
                  and their active sessions end immediately. The account is kept
                  and can be restored.
                </>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>

          {error && (
            <p className="text-sm text-red-600 whitespace-pre-wrap">{error}</p>
          )}

          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={busy}
              onClick={(e) => {
                // Keep the dialog open so a refusal is readable; it closes on success.
                e.preventDefault();
                void run();
              }}
            >
              {busy ? "Working…" : isDeleted ? "Restore" : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
