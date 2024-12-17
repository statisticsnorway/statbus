BEGIN;

INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('employees','int','yearly','Employees','The number of people receiving an official salary with government reporting.',1),
  ('turnover','float','yearly','Turnover','The amount (Local Currency)',2);
END;
