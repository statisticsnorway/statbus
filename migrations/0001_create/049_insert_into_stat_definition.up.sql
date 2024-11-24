BEGIN;

INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('employees','int','yearly','Number of people employed','The number of people receiving an official salary with government reporting.',1),
  ('turnover','int','yearly','Turnover','The amount (EUR)',2);

END;