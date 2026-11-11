'use client'
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { toast } from "@/hooks/use-toast";
import { useState } from "react";
import { Loader2 } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "../ui/dialog";
import { Input } from "../ui/input";
import { Button } from "../ui/button";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { recreateApiKey, type ApiKeyRow } from "@/lib/api-key";

type ShownKey = ApiKeyRow & { token: string };

/**
 * "Show API key" from the command palette: the user's active key (the newest
 * one not revoked), to copy. Recreate replaces it with a new key and revokes
 * the shown one (recreateApiKey, STATBUS-617), for a key that was exposed.
 */
export function ApiKeyDialog() {
  const [open, setOpen] = useState(false);
  const [apiKey, setApiKey] = useState<ShownKey | null>(null);
  const [recreating, setRecreating] = useState(false);

  useGuardedEffect(
    () => {
      const showDialog = async () => {
        setOpen(true);
        try {
          const client = await getBrowserRestClient();
          const { data, error } = await client
            .from("api_key")
            .select("jti,description,created_at,expires_at,token")
            .is("revoked_at", null)
            .order("created_at", { ascending: false })
            .limit(1);
          if (error) {
            throw new Error(`API key fetch failed: ${error.message}`);
          }
          const key = data?.[0];
          if (key?.token && key.jti) {
            setApiKey(key as ShownKey);
          } else {
            throw new Error("API key invalid or not found");
          }
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
      const created = await recreateApiKey(client, apiKey);
      setApiKey({ ...apiKey, jti: created.jti, token: created.token });
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

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Your API Key</DialogTitle>
          <DialogDescription>
            Copy the API key below. If it has been shared or exposed, recreate it: the current key stops working at once.
          </DialogDescription>
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
        <div className="flex justify-end">
          <Button variant="outline" size="sm" onClick={handleRecreate} disabled={!apiKey || recreating}>
            {recreating ? (
              <>
                <Loader2 className="animate-spin" aria-hidden />
                Recreating…
              </>
            ) : (
              "Recreate key"
            )}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
