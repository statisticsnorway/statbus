

Select 'Runs Uganda Kampala'  "StatbusStatus", now() "AT";

delete from external_ident_type where code in ('tax_ident','stat_ident');


INSERT INTO external_ident_type (code, name, priority)
VALUES
('coin_ident', 'CoinId', 3);


--custom datasources can be listed here:
--delete from data_source_custom ;
--INSERT INTO data_source_custom (code, name)
--VALUES
  --  ('tst', 'Test'),
 --   ('cen25', 'Census2025');



delete from stat_definition where id >2;
INSERT INTO stat_definition (code, type,frequency, name, priority)
VALUES
('female', 'int', 'yearly', 'Female', 3),
('male', 'int', 'yearly', 'Male', 4);


Select 'Done Uganda'  "StatbusStatus", now() "AT";
