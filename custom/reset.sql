
--reset when swaping country from one country to another country in ie demo.statbus.org
--shouls not be needed going forward..
--erik kenya

CREATE OR REPLACE PROCEDURE public.custom_setup_reset()
LANGUAGE plpgsql
AS $BODY$
BEGIN

	--sletter custom
    DELETE FROM external_ident_type
    WHERE code NOT IN ('tax_ident', 'stat_ident');
	
	--alle disse henger igjen - de lanspesfike stat variabler
	delete from import_source_column
	where column_name in ('male','punpag','selfemp','female', 'jor', 'nonjor','reg_capital', 'cur_capital' , 'share_capital', 'sales', 'production');

	--viser de begge de som er default de over
	UPDATE external_ident_type
    SET archived = FALSE
    WHERE id <= 2; --not needed

	DELETE FROM data_source_custom;

  	DELETE FROM stat_definition
  	WHERE code NOT IN ('employees', 'turnover');

  	DELETE FROM unit_size
    WHERE id > 4 AND custom = TRUE;

	DELETE FROM status
    WHERE id > 2 AND custom = TRUE;
	
	
--mangler evt jo ug custom to be deleted..	
delete from  public.import_source_column 
where 1 = 1
and column_name in 
('legal_unit_krapin', 'legal_unit_brs', 'legal_unit_nssf', 'legal_unit_sbp', 'legal_unit_nhif', 'krapin', 'brs', 'nssf', 'sbp', 'nhif','ice_ident', 'hcp_ident', 'cnss_ident', 'share_capital','legal_unit_national_id', 'national_id','legal_unit_ice_ident', 'legal_unit_cnss_ident', 'legal_unit_hcp_ident') ; -- 32 rader rester av morocco som jeg sletter

--default
update stat_definition
set archived = FALSE
WHERE code IN ('employees', 'turnover');

--default
update status
set active = TRUE
where custom = FALSE;


--default
update unit_size
set active = TRUE
where custom = FALSE;

	

End;
$BODY$;
