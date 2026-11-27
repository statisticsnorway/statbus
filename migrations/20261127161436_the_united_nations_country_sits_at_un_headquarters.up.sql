-- Migration 20261127161436: the United Nations country sits at UN Headquarters
--
-- The United Nations (UN) is the country of demo and test installations and has
-- no geographic centre. Migration 20261123114610 placed it at 0,0, which the
-- world map draws in the Gulf of Guinea. It is placed at UN Headquarters in New
-- York, where a reader looks for it (owner 2026-11-27, 5necw2), as
-- dbseed/country/country_centres.csv now ships it. Installed databases got 0,0
-- from that file; this sets the same fixed value, so a full replay and an
-- upgrade end alike.
BEGIN;

UPDATE public.country
   SET latitude = 40.748900, longitude = -73.968000
 WHERE iso_2 = 'UN';

END;
