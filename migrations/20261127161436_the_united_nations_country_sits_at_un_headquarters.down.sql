-- Down Migration 20261127161436: the United Nations country back at 0,0
BEGIN;

UPDATE public.country
   SET latitude = 0, longitude = 0
 WHERE iso_2 = 'UN';

END;
