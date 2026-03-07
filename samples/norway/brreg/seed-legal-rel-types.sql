-- Seed legal_rel_type with BRREG role codes for legal relationships.
-- primary_influencer_only = TRUE means this type forms power group hierarchies
-- (guaranteed single root per influenced unit via exclusion constraint).
INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only) VALUES
    ('HFOR', 'Hovedforetak', 'Parent company (hovedforetak) relationship', TRUE),
    ('DTPR', 'Deltaker pro-rata', 'Partner with proportional liability', FALSE),
    ('DTSO', 'Deltaker solidarisk', 'Partner with joint liability', FALSE),
    ('EIKM', 'Eierkommune', 'Owner municipality', TRUE),
    ('KOMP', 'Komplementar', 'General partner (komplementar)', TRUE)
ON CONFLICT (code) DO UPDATE SET
    primary_influencer_only = EXCLUDED.primary_influencer_only;
