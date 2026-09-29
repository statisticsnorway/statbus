-- Upgrade-arc FAILING fixture (STATBUS-071 d): deterministic failure → rollback.
DO $$ BEGIN
  RAISE EXCEPTION 'upgrade-arc failing fixture: deliberate migration failure (STATBUS-071 d)';
END $$;
