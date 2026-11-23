---
id: nq8zqt
title: "Geocoding workflows propose coordinates as an import job"
state: todo
type: feature
priority: ""
assignee: []
labels: ["maps"]
group: ""
rank: "zzzzzzq"
created: 2026-11-22
updated: 2026-11-22
---

## Goal
A workflow looks up units' (or regions') addresses and proposes their coordinates as an import job to review and apply.

## Purpose
Owner 2026-11-22 (z2qt08 answer 5): coordinates come from workflows, not from the location picker or installation. One uses Kartverket for Norway, another OpenStreetMap, possibly with an API key the office enters itself, configured as it is used. Coordinates are what the maps of z2qt08 show.

## Principle
Nothing changes the data except the import job the workflow produces (xhxnsy's contract): the user sees each proposed coordinate before applying. Built step by step: one provider first.

## Details
Kartverket's address API (ws.geonorge.no/adresser/v1) is open but not meant for whole datasets; for a full register Geonorge's downloadable address files are recommended. OpenStreetMap's public Nominatim allows 1 request per second and no bulk geocoding, so a register-sized run needs a key or own instance. Region centres: public.region.center_latitude/longitude, 24 Norway regions lack one today. Depends on the Workflows page (xhxnsy) and on an import that sets only coordinates on existing units (dbmsxy).

## Depends on
- xhxnsy
- dbmsxy

## Acceptance
- [ ] [Owner] Decides the first provider, its configuration (where an API key is entered) and whether units or region centres come first; recorded in this task's notes
- [ ] Running the first geocoding workflow on a chosen frame produces an import job whose rows are the proposed coordinates, shown in the import review before anything is applied
- [ ] Applying the job sets the units' (or regions') coordinates and nothing else, shown by a SQL test on the stored rows

## Notes

2026-11-23 (hibiscus, owner's review of z2qt08) Each unit now has a Map page (/establishments|legal-units|enterprises/[id]/map, branch feat/units-on-map). It places a unit without coordinates at its region's centre as a ring ('somewhere in its region'). The owner wants a sensible way to set a unit's pin, like 'Place on map' for regions. Proposed entry point: a 'Look up from address' action for units that have only a region, on the Map page and on the location form. It uses the unit's own address (geocoding, this workflow), not a name search. Units at the same address get the same point; the Map page then shows them together as the page's unit '+n'.
