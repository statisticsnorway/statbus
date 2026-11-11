'use client'
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { toast } from "@/hooks/use-toast";
import { useState } from "react";
import { useAtomValue } from "jotai";
import { Loader2 } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "../ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "../ui/alert-dialog";
import { Input } from "../ui/input";
import { Button } from "../ui/button";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { currentUserAtom } from "@/atoms/auth";
import { keyValidity, recreateApiKey, tokenDisplayName, type ApiKeyRow } from "@/lib/api-key";

type ShownKey = ApiKeyRow & { token: string };

/**
 * "Show API key" from the command palette. A user may hold several keys
 * (public.api_key, one row per key); the dialog shows the active one most
 * recently created, with its description, creation date and how long it stays
 * valid, the name it carries, and how many active keys the user has. The name
 * is fixed when the key is created, and tools that read the key (the
 * www.statbus.org course certificate) show it; when the profile name has
 * changed since, the dialog says so. Recreate key (after a confirmation)
 * replaces the shown key with a new one and revokes it (recreateApiKey,
 * STATBUS-617), for a key that was exposed or carries an outdated name.
 */
export function ApiKeyDialog() {
  const currentUser = useAtomValue(currentUserAtom);
  const [open, setOpen] = useState(false);
  const [apiKey, setApiKey] = useState<ShownKey | null>(null);
  const [activeCount, setActiveCount] = useState(0);
  const [confirming, setConfirming] = useState(false);
  const [recreating, setRecreating] = useState(false);

  const loadActiveKey = async () => {
    const client = await getBrowserRestClient();
    const { data, error } = await client
      .from("api_key")
      .select("jti,description,created_at,expires_at,token")
      .is("revoked_at", null)
      .order("created_at", { ascending: false });
    if (error) {
      throw new Error(`API key fetch failed: ${error.message}`);
    }
    const key = data?.[0];
    if (!key?.token || !key.jti) {
      throw new Error("API key invalid or not found");
    }
    setApiKey(key as ShownKey);
    setActiveCount(data.length);
  };

  useGuardedEffect(
    () => {
      const showDialog = async () => {
        setOpen(true);
        try {
          await loadActiveKey();
        } catch (error) {
          console.error("Failed to fetch API key:", error);
          toast({
            title: "Failed to fetch API key",
            description: "An error occurred.",
            variant: "destructive",
          });
          setOpen(false);
        }
      };

      document.addEventListener('show-api-key-dialog', showDialog);
      return () => {
        document.removeEventListener('show-api-key-dialog', showDialog);
      };
    },
    [],
    'ApiKeyDialog:showDialogListener'
  );

  const handleCopy = async () => {
    if (apiKey) {
      await navigator.clipboard.writeText(apiKey.token);
      toast({
        title: 'Copied to clipboard!',
      });
      setOpen(false);
    }
  };

  const handleRecreate = async () => {
    if (!apiKey) return;
    setRecreating(true);
    try {
      const client = await getBrowserRestClient();
      await recreateApiKey(client, apiKey);
      await loadActiveKey();
      setConfirming(false);
      toast({
        title: "New API key created",
        description: "The previous key no longer works. Copy the new one.",
      });
    } catch (error) {
      console.error("Failed to recreate API key:", error);
      toast({
        title: "Failed to recreate API key",
        description: error instanceof Error ? error.message : "An error occurred.",
        variant: "destructive",
      });
    } finally {
      setRecreating(false);
    }
  };

  const validity = keyValidity(apiKey?.expires_at ?? null);
  const keyName = apiKey ? tokenDisplayName(apiKey.token) : null;
  const profileName = currentUser?.display_name ?? null;
  const nameOutdated = !!keyName && !!profileName && keyName !== profileName;

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Your API Key</DialogTitle>
          <DialogDescription>Copy the API key below to use the REST API from scripts and tools.</DialogDescription>
        </DialogHeader>
        <div className="flex items-center space-x-2">
          <Input
            value={apiKey?.token ?? "Loading..."}
            readOnly
            className="font-mono bg-zinc-50"
            data-api-key-jti={apiKey?.jti}
          />
          <Button onClick={handleCopy} disabled={!apiKey || recreating}>
            Copy
          </Button>
        </div>
        {apiKey && (
          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-sm" data-api-key-details>
            <dt className="text-zinc-500">Description</dt>
            <dd>{apiKey.description ?? "—"}</dd>
            <dt className="text-zinc-500">Name in key</dt>
            <dd data-api-key-name={keyName ?? undefined}>
              {keyName ?? "—"}
              {nameOutdated && (
                <span className="block text-red-600" data-api-key-name-outdated>
                  Your profile name is now {profileName}. Recreate the key to carry it.
                </span>
              )}
            </dd>
            <dt className="text-zinc-500">Created</dt>
            <dd>{apiKey.created_at?.slice(0, 10) ?? "—"}</dd>
            <dt className="text-zinc-500">Valid until</dt>
            <dd data-api-key-valid-until={validity?.validUntil}>
              {validity ? (
                <>
                  {validity.validUntil}{" "}
                  <span className={validity.expired || validity.daysLeft < 30 ? "text-red-600" : "text-zinc-500"}>
                    ({validity.expired ? "expired" : `${validity.daysLeft} days left`})
                  </span>
                </>
              ) : (
                "No expiry"
              )}
            </dd>
            {activeCount > 1 && (
              <>
                <dt className="text-zinc-500">Active keys</dt>
                <dd>{activeCount} (the newest is shown)</dd>
              </>
            )}
          </dl>
        )}
        <div className="flex justify-end">
          <Button variant="outline" size="sm" onClick={() => setConfirming(true)} disabled={!apiKey || recreating}>
            Recreate key
          </Button>
        </div>
      </DialogContent>
      <AlertDialog open={confirming} onOpenChange={(next) => !recreating && setConfirming(next)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Recreate this API key?</AlertDialogTitle>
            <AlertDialogDescription>
              A new key is created and this one stops working at once. Scripts and tools that use it must be given the
              new key. Do this when the key has been shared or exposed.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={recreating}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={recreating}
              onClick={(e) => {
                // Stay open until the new key is in place; it closes on success.
                e.preventDefault();
                void handleRecreate();
              }}
            >
              {recreating ? (
                <>
                  <Loader2 className="animate-spin" aria-hidden />
                  Recreating…
                </>
              ) : (
                "Recreate key"
              )}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Dialog>
  );
}
