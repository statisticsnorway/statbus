'use client'
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { toast } from "@/hooks/use-toast";
import { useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "../ui/dialog";
import { Input } from "../ui/input";
import { Button } from "../ui/button";
import { getBrowserRestClient } from "@/context/RestClientStore";


export function ApiKeyDialog() {
 const [open, setOpen] = useState(false);
 const [apiKey, setApiKey] = useState<string|null>(null)                                                                                                                                                         
                                                                                                                                                                                               
  useGuardedEffect(                                                                                                                                                                            
    () => {                                                                                                                                                                                    
      const showDialog = async () => {                                                                                                                                                         
        setOpen(true);                                                                                                                                                                         
        try {
          const client = await getBrowserRestClient();
          const { data, error } = await client.from("api_key").select("token");
          if (error) {
            throw new Error(`API key fetch failed: ${error.message}`);
          }
          const key = data?.[0]?.token;
          if (key) {
            setApiKey(key);
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
      await navigator.clipboard.writeText(apiKey);                                                                                                                                             
      toast({                                                                                                                                                                                  
        title: 'Copied to clipboard!',                                                                                                                                                         
      });                                                                                                                                                                                      
      setOpen(false);                                                                                                                                                                          
    }                                                                                                                                                                                          
  };                                                                                                                                                                                           
                                                                                                                                                                                               
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Your API Key</DialogTitle>
          <DialogDescription>Copy the API key below.</DialogDescription>
        </DialogHeader>
        <div className="flex items-center space-x-2">
          <Input
            value={apiKey ?? "Loading..."}
            readOnly
            className="font-mono bg-zinc-50"
          />
          <Button onClick={handleCopy} disabled={!apiKey}>
            Copy
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );                                                                                                                                                                                           
}