-- Down Migration 20260712024457: upgrade block terminal resurrection statbus 160
BEGIN;

DROP TRIGGER upgrade_block_terminal_resurrection_trigger ON public.upgrade;
DROP FUNCTION public.upgrade_block_terminal_resurrection();

END;
