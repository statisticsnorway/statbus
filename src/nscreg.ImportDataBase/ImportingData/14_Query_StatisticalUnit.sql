ALTER TABLE [dbo].[StatisticalUnits]
ADD K_PRED FLOAT NULL
GO

--ALTER TABLE [dbo].[StatisticalUnits] DROP K_PRED

DELETE FROM [StatisticalUnits]
GO
DBCC CHECKIDENT ('dbo.StatisticalUnits',RESEED, 1)
GO

DECLARE @guid NVARCHAR(450)
SELECT @guid = Id FROM [dbo].[AspNetUsers]

INSERT INTO [dbo].[StatisticalUnits]
  ([ActualAddressId]
	,[AddressId]
	,[ChangeReason]
	,[Classified]
	,[DataSource]
	,[DataSourceClassificationId]
	,[Discriminator]
	,[EditComment]
	,[EmailAddress]
  ,[Employees]
	,[EmployeesDate]
	,[EmployeesYear]
	,[EndPeriod]
	,[ExternalId]
	,[ExternalIdDate]
	,[ExternalIdType]
	,[ForeignParticipationCountryId]
  ,[ForeignParticipationId]
	,[FreeEconZone]
	,[InstSectorCodeId]
	,[IsDeleted]
	,[LegalFormId]
	,[LiqDate]
	,[LiqReason]
	,[Name]
	,[Notes]
	,[NumOfPeopleEmp]
  ,[ParentOrgLink]
	,[PostalAddressId]
	,[RefNo]
	,[RegIdDate]
	,[RegistrationDate]
	,[ReorgDate]
	,[ReorgReferences]
  ,[ReorgTypeCode]
	,[ReorgTypeId]
	,[ShortName]
	,[SizeId]
	,[StartPeriod]
	,[StatId]
	,[StatIdDate]
	,[StatusDate]
	,[SuspensionEnd]
	,[SuspensionStart]
  ,[TaxRegDate]
	,[TaxRegId]
	,[TelephoneNo]
	,[Turnover]
	,[TurnoverDate]
	,[TurnoverYear]
	,[UnitStatusId]
	,[UserId]
	,[WebAddress]
	,[Commercial]
  ,[EntGroupId]
	,[EntGroupIdDate]
	,[EntGroupRole]
	,[ForeignCapitalCurrency]
	,[ForeignCapitalShare]
	,[MunCapitalShare]
	,[PrivCapitalShare]
	,[StateCapitalShare]
	,[TotalCapital]
	,[EntRegIdDate]
	,[EnterpriseUnitRegId]
	,[Market]
	,[LegalUnitId]
	,[LegalUnitIdDate]
	,[RegistrationReasonId]
	,[K_PRED])
SELECT
	a.Address_id AS ActualAddressId,
	a.Address_id AS AddressId,
	0 AS ChangeReason,
	NULL AS Classified,
  NULL AS DataSource, -- Data source upload functionality, places name of file from which was uploaded
  NULL AS DataSourceClassificationId, -- Data source classifications catalogue row Id
  CASE
		WHEN K_PME = 0 THEN 'LegalUnit'
		ELSE 'LocalUnit'
	END AS Discriminator,
	NULL AS EditComment,
	E_MAIL AS EmailAddress,
	S_SPR1 AS Employees,
	GETDATE() AS EmployeesDate,
	YEAR(GETDATE()) AS EmployeesYear,
  '9999-12-31 23:59:59.9999999' AS EndPeriod,
	REG_J AS ExternalId ,
	D_R_J AS ExternalIdDate,
	0 AS ExternalIdType,
  NULL AS ForeignParticipationCountryId,
  fp.Id AS ForeignParticipationId, -- Foreign participations catalogue row Id
	SEZ AS FreeEconZone,
  s.Id AS InstSectorCodeId, -- Sector codes catalogue row Id
	0 AS IsDeleted,
	l.Id AS LegalFormId,
  NULL AS LiqDate, -- LIQDATE set a column name if it exists in source db
	NULL AS LiqReason,
	NAME_S AS Name,
	NULL AS Notes,
	S_SPR1 AS NumOfPeopleEmp,
	NULL as ParentOrgLink,
  NULL AS PostalAddressId,
	a.Address_id AS PostalAddressId,
  0 AS RefNo,
	GETDATE() AS RegIdDate,
	ISNULL(D_VVOD, GETDATE()) AS RegistrationDate,
	GETDATE() AS ReorgDate,
	NULL AS ReorgReferences,
	NULL AS ReorgTypeCode,
  NULL AS ReorgTypeId, -- Reorg type catalogue row Id
  NULL AS ShortName,
  NULL AS SizeId,
  GETDATE() AS StartPeriod,
	k.K_PRED AS StatId,
	GETDATE() AS StatIdDate,
	GETDATE() AS StatusDate,
	DVD AS SuspensionEnd,
	DPD AS SuspensionStart,
  GETDATE() AS TaxRegDate,
	K_SOC AS TaxRegId,
	ISNULL(T_ON + ', ', '') + ISNULL(T_FAKS, '') AS TelephoneNo,
  V_PRI AS Turnover,
  GETDATE() AS TurnoverDate,
  YEAR(GETDATE()) AS TurnoverYear,
  L_PRI AS UnitStatusId, -- Statuses catalogue row Id
  @guid AS UserId,
	NULL AS WebAddress,
  CASE
		WHEN V_DE = 0 OR V_DE = 1 THEN 0
		ELSE 1
	END AS Commercial,
	NULL AS EntGroupId,
	NULL AS EntGroupIdDate,
	NULL AS EntGroupRole,
  NULL AS ForeignCapitalCurrency,
	NULL AS ForeignCapitalShare,
	NULL AS MunCapitalShare,
	NULL AS PrivCapitalShare,
	NULL AS StateCapitalShare,
  USTV AS TotalCapital,
	NULL AS EntRegIdDate,
  NULL AS EnterpriseUnitRegId,
	CASE
		WHEN V_DE = 0 OR V_DE = 1 THEN 0
		ELSE 1
	END AS Market,
	NULL AS LegalUnitId,
	GETDATE() AS LegalUnitIdDate,
	NULL AS RegistrationReasonId, -- Registration reason catalogue row Id
	k.K_PRED AS K_PRED
FROM [statcom].[dbo].[KATME] k
INNER JOIN [dbo].[Address] AS a
	ON a.K_PRED = k.K_PRED
LEFT JOIN [dbo].[SectorCodes] s
	ON s.Code = k.SEK_EK
LEFT JOIN [dbo].[LegalForms] l
	ON CAST(LEFT(k.KTP,2) AS INT) = l.Code
LEFT JOIN [dbo].[ForeignParticipations] fp
	ON fp.Id = SUBSTRING(CAST(KTP AS VARCHAR(100)), 4, 1)
-- LEFT JOIN [dbo].[Statuses] statusestb
--     ON statusestb.Id= k.StatusesTableIfExists
GO

-- Add Legal Units And Links To Existing Local Units --

INSERT INTO [dbo].[StatisticalUnits]
  ([ActualAddressId]
  ,[AddressId]
  ,[ChangeReason]
  ,[Classified]
  ,[DataSource]
  ,[DataSourceClassificationId]
  ,[Discriminator]
  ,[EditComment]
  ,[EmailAddress]
  ,[Employees]
  ,[EmployeesDate]
  ,[EmployeesYear]
  ,[EndPeriod]
  ,[ExternalId]
  ,[ExternalIdDate]
  ,[ExternalIdType]
  ,[ForeignParticipationCountryId]
  ,[ForeignParticipationId]
  ,[FreeEconZone]
  ,[InstSectorCodeId]
  ,[IsDeleted]
  ,[LegalFormId]
  ,[LiqDate]
  ,[LiqReason]
  ,[Name]
  ,[Notes]
  ,[NumOfPeopleEmp]
  ,[ParentOrgLink]
  ,[RefNo]
  ,[RegIdDate]
  ,[RegistrationDate]
  ,[ReorgDate]
  ,[ReorgReferences]
  ,[ReorgTypeCode]
  ,[ReorgTypeId]
  ,[ShortName]
  ,[SizeId]
  ,[StartPeriod]
  ,[StatId]
  ,[StatIdDate]
  ,[StatusDate]
  ,[SuspensionEnd]
  ,[SuspensionStart]
  ,[TaxRegDate]
  ,[TaxRegId]
  ,[TelephoneNo]
  ,[Turnover]
  ,[TurnoverDate]
  ,[TurnoverYear]
  ,[UnitStatusId]
  ,[UserId]
  ,[WebAddress]
  ,[Commercial]
  ,[EntGroupId]
  ,[EntGroupIdDate]
  ,[EntGroupRole]
  ,[ForeignCapitalCurrency]
  ,[ForeignCapitalShare]
  ,[HistoryLegalUnitIds]
  ,[MunCapitalShare]
  ,[PrivCapitalShare]
  ,[StateCapitalShare]
  ,[TotalCapital]
  ,[EntRegIdDate]
  ,[EnterpriseUnitRegId]
  ,[HistoryLocalUnitIds]
  ,[Market]
  ,[LegalUnitId]
  ,[LegalUnitIdDate]
  ,[RegistrationReasonId]
  ,[PostalAddressId]
  ,[K_PRED])
SELECT
  [ActualAddressId]
  ,[AddressId]
  ,[ChangeReason]
  ,[Classified]
  ,[DataSource]
  ,[DataSourceClassificationId]
  ,'LegalUnit' AS [Discriminator]
  ,[EditComment]
  ,[EmailAddress]
  ,[Employees]
  ,[EmployeesDate]
  ,[EmployeesYear]
  ,[EndPeriod]
  ,[ExternalId]
  ,[ExternalIdDate]
  ,[ExternalIdType]
  ,[ForeignParticipationCountryId]
  ,[ForeignParticipationId]
  ,[FreeEconZone]
  ,[InstSectorCodeId]
  ,[IsDeleted]
  ,[LegalFormId]
  ,[LiqDate]
  ,[LiqReason]
  ,[Name]
  ,[Notes]
  ,[NumOfPeopleEmp]
  ,[ParentOrgLink]
  ,[RefNo]
  ,[RegIdDate]
  ,[RegistrationDate]
  ,[ReorgDate]
  ,[ReorgReferences]
  ,[ReorgTypeCode]
  ,[ReorgTypeId]
  ,[ShortName]
  ,[SizeId]
  ,[StartPeriod]
  ,[StatId]
  ,[StatIdDate]
  ,[StatusDate]
  ,[SuspensionEnd]
  ,[SuspensionStart]
  ,[TaxRegDate]
  ,[TaxRegId]
  ,[TelephoneNo]
  ,[Turnover]
  ,[TurnoverDate]
  ,[TurnoverYear]
  ,[UnitStatusId]
  ,[UserId]
  ,[WebAddress]
  ,[Commercial]
  ,[EntGroupId]
  ,[EntGroupIdDate]
  ,[EntGroupRole]
  ,[ForeignCapitalCurrency]
  ,[ForeignCapitalShare]
  ,[HistoryLegalUnitIds]
  ,[MunCapitalShare]
  ,[PrivCapitalShare]
  ,[StateCapitalShare]
  ,[TotalCapital]
  ,[EntRegIdDate]
  ,[EnterpriseUnitRegId]
  ,[HistoryLocalUnitIds]
  ,[Market]
  ,[LegalUnitId]
  ,[LegalUnitIdDate]
  ,[RegistrationReasonId]
  ,[PostalAddressId]
  ,NULL AS [K_PRED]
FROM	dbo.StatisticalUnits
WHERE Discriminator = 'LocalUnit'
GO

UPDATE s SET
	s.LegalUnitId = s2.RegId
FROM dbo.StatisticalUnits s
INNER JOIN dbo.StatisticalUnits s2
	ON s.Name = s2.Name
		AND s.ActualAddressId = s2.ActualAddressId
		AND s.AddressId = s2.AddressId
		AND s.Employees = s2.Employees
		AND s2.Discriminator = 'LegalUnit'
WHERE s.Discriminator = 'LocalUnit'
GO


-- Add Local Units And Links To Existing LegalUnits --

INSERT INTO [dbo].[StatisticalUnits]
  ([ActualAddressId]
  ,[AddressId]
  ,[ChangeReason]
  ,[Classified]
  ,[DataSource]
  ,[DataSourceClassificationId]
  ,[Discriminator]
  ,[EditComment]
  ,[EmailAddress]
  ,[Employees]
  ,[EmployeesDate]
  ,[EmployeesYear]
  ,[EndPeriod]
  ,[ExternalId]
  ,[ExternalIdDate]
  ,[ExternalIdType]
  ,[ForeignParticipationCountryId]
  ,[ForeignParticipationId]
  ,[FreeEconZone]
  ,[InstSectorCodeId]
  ,[IsDeleted]
  ,[LegalFormId]
  ,[LiqDate]
  ,[LiqReason]
  ,[Name]
  ,[Notes]
  ,[NumOfPeopleEmp]
  ,[ParentOrgLink]
  ,[RefNo]
  ,[RegIdDate]
  ,[RegistrationDate]
  ,[ReorgDate]
  ,[ReorgReferences]
  ,[ReorgTypeCode]
  ,[ReorgTypeId]
  ,[ShortName]
  ,[SizeId]
  ,[StartPeriod]
  ,[StatId]
  ,[StatIdDate]
  ,[StatusDate]
  ,[SuspensionEnd]
  ,[SuspensionStart]
  ,[TaxRegDate]
  ,[TaxRegId]
  ,[TelephoneNo]
  ,[Turnover]
  ,[TurnoverDate]
  ,[TurnoverYear]
  ,[UnitStatusId]
  ,[UserId]
  ,[WebAddress]
  ,[Commercial]
  ,[EntGroupId]
  ,[EntGroupIdDate]
  ,[EntGroupRole]
  ,[ForeignCapitalCurrency]
  ,[ForeignCapitalShare]
  ,[HistoryLegalUnitIds]
  ,[MunCapitalShare]
  ,[PrivCapitalShare]
  ,[StateCapitalShare]
  ,[TotalCapital]
  ,[EntRegIdDate]
  ,[EnterpriseUnitRegId]
  ,[HistoryLocalUnitIds]
  ,[Market]
  ,[LegalUnitId]
  ,[LegalUnitIdDate]
  ,[RegistrationReasonId]
  ,[PostalAddressId]
  ,[K_PRED])
SELECT
  [ActualAddressId]
  ,[AddressId]
  ,[ChangeReason]
  ,[Classified]
  ,[DataSource]
  ,[DataSourceClassificationId]
  ,'LocalUnit' AS [Discriminator]
  ,[EditComment]
  ,[EmailAddress]
  ,[Employees]
  ,[EmployeesDate]
  ,[EmployeesYear]
  ,[EndPeriod]
  ,[ExternalId]
  ,[ExternalIdDate]
  ,[ExternalIdType]
  ,[ForeignParticipationCountryId]
  ,[ForeignParticipationId]
  ,[FreeEconZone]
  ,[InstSectorCodeId]
  ,[IsDeleted]
  ,[LegalFormId]
  ,[LiqDate]
  ,[LiqReason]
  ,[Name]
  ,[Notes]
  ,[NumOfPeopleEmp]
  ,[ParentOrgLink]
  ,[RefNo]
  ,[RegIdDate]
  ,[RegistrationDate]
  ,[ReorgDate]
  ,[ReorgReferences]
  ,[ReorgTypeCode]
  ,[ReorgTypeId]
  ,[ShortName]
  ,[SizeId]
  ,[StartPeriod]
  ,[StatId]
  ,[StatIdDate]
  ,[StatusDate]
  ,[SuspensionEnd]
  ,[SuspensionStart]
  ,[TaxRegDate]
  ,[TaxRegId]
  ,[TelephoneNo]
  ,[Turnover]
  ,[TurnoverDate]
  ,[TurnoverYear]
  ,[UnitStatusId]
  ,[UserId]
  ,[WebAddress]
  ,[Commercial]
  ,[EntGroupId]
  ,[EntGroupIdDate]
  ,[EntGroupRole]
  ,[ForeignCapitalCurrency]
  ,[ForeignCapitalShare]
  ,[HistoryLegalUnitIds]
  ,[MunCapitalShare]
  ,[PrivCapitalShare]
  ,[StateCapitalShare]
  ,[TotalCapital]
  ,[EntRegIdDate]
  ,[EnterpriseUnitRegId]
  ,[HistoryLocalUnitIds]
  ,NULL AS [Market]
  ,[LegalUnitId]
  ,[LegalUnitIdDate]
  ,[RegistrationReasonId]
  ,[PostalAddressId]
  ,NULL AS [K_PRED]
FROM	dbo.StatisticalUnits
WHERE Discriminator = 'LegalUnit' AND K_PRED IS NOT NULL
GO

UPDATE s SET
	s.LegalUnitId = s2.RegId
FROM dbo.StatisticalUnits s
INNER JOIN dbo.StatisticalUnits s2
	ON s.Name = s2.Name
		AND s.ActualAddressId = s2.ActualAddressId
		AND s.AddressId = s2.AddressId
		AND s.Employees = s2.Employees
		AND s2.Discriminator = 'LegalUnit'
WHERE s.Discriminator = 'LocalUnit' AND s.K_PRED IS NULL
GO


-- Add Enterprise Units And Links To Existing Legal Units --

INSERT INTO [dbo].[StatisticalUnits]
  ([ActualAddressId]
  ,[AddressId]
  ,[ChangeReason]
  ,[Classified]
  ,[DataSource]
  ,[DataSourceClassificationId]
  ,[Discriminator]
  ,[EditComment]
  ,[EmailAddress]
  ,[Employees]
  ,[EmployeesDate]
  ,[EmployeesYear]
  ,[EndPeriod]
  ,[ExternalId]
  ,[ExternalIdDate]
  ,[ExternalIdType]
  ,[ForeignParticipationCountryId]
  ,[ForeignParticipationId]
  ,[FreeEconZone]
  ,[InstSectorCodeId]
  ,[IsDeleted]
  ,[LegalFormId]
  ,[LiqDate]
  ,[LiqReason]
  ,[Name]
  ,[Notes]
  ,[NumOfPeopleEmp]
  ,[ParentOrgLink]
  ,[RefNo]
  ,[RegIdDate]
  ,[RegistrationDate]
  ,[ReorgDate]
  ,[ReorgReferences]
  ,[ReorgTypeCode]
  ,[ReorgTypeId]
  ,[ShortName]
  ,[SizeId]
  ,[StartPeriod]
  ,[StatId]
  ,[StatIdDate]
  ,[StatusDate]
  ,[SuspensionEnd]
  ,[SuspensionStart]
  ,[TaxRegDate]
  ,[TaxRegId]
  ,[TelephoneNo]
  ,[Turnover]
  ,[TurnoverDate]
  ,[TurnoverYear]
  ,[UnitStatusId]
  ,[UserId]
  ,[WebAddress]
  ,[Commercial]
  ,[EntGroupId]
  ,[EntGroupIdDate]
  ,[EntGroupRole]
  ,[ForeignCapitalCurrency]
  ,[ForeignCapitalShare]
  ,[HistoryLegalUnitIds]
  ,[MunCapitalShare]
  ,[PrivCapitalShare]
  ,[StateCapitalShare]
  ,[TotalCapital]
  ,[EntRegIdDate]
  ,[EnterpriseUnitRegId]
  ,[HistoryLocalUnitIds]
  ,[Market]
  ,[LegalUnitId]
  ,[LegalUnitIdDate]
  ,[RegistrationReasonId]
  ,[PostalAddressId]
  ,[K_PRED])
SELECT
  [ActualAddressId]
  ,[AddressId]
  ,[ChangeReason]
  ,[Classified]
  ,[DataSource]
  ,[DataSourceClassificationId]
  ,'EnterpriseUnit' AS [Discriminator]
  ,[EditComment]
  ,[EmailAddress]
  ,[Employees]
  ,[EmployeesDate]
  ,[EmployeesYear]
  ,[EndPeriod]
  ,[ExternalId]
  ,[ExternalIdDate]
  ,[ExternalIdType]
  ,[ForeignParticipationCountryId]
  ,[ForeignParticipationId]
  ,[FreeEconZone]
  ,[InstSectorCodeId]
  ,[IsDeleted]
  ,[LegalFormId]
  ,[LiqDate]
  ,[LiqReason]
  ,[Name]
  ,[Notes]
  ,[NumOfPeopleEmp]
  ,[ParentOrgLink]
  ,[RefNo]
  ,[RegIdDate]
  ,[RegistrationDate]
  ,[ReorgDate]
  ,[ReorgReferences]
  ,[ReorgTypeCode]
  ,[ReorgTypeId]
  ,[ShortName]
  ,[SizeId]
  ,[StartPeriod]
  ,[StatId]
  ,[StatIdDate]
  ,[StatusDate]
  ,[SuspensionEnd]
  ,[SuspensionStart]
  ,[TaxRegDate]
  ,[TaxRegId]
  ,[TelephoneNo]
  ,[Turnover]
  ,[TurnoverDate]
  ,[TurnoverYear]
  ,[UnitStatusId]
  ,[UserId]
  ,[WebAddress]
  ,[Commercial]
  ,[EntGroupId]
  ,GETDATE() AS [EntGroupIdDate]
  ,[EntGroupRole]
  ,[ForeignCapitalCurrency]
  ,[ForeignCapitalShare]
  ,[HistoryLegalUnitIds]
  ,[MunCapitalShare]
  ,[PrivCapitalShare]
  ,[StateCapitalShare]
  ,[TotalCapital]
  ,[EntRegIdDate]
  ,[EnterpriseUnitRegId]
  ,[HistoryLocalUnitIds]
  ,[Market]
  ,[LegalUnitId]
  ,[LegalUnitIdDate]
  ,[RegistrationReasonId]
  ,[PostalAddressId]
  ,NULL AS [K_PRED]
FROM [dbo].[StatisticalUnits]
WHERE Discriminator = 'LegalUnit' AND K_PRED IS NOT NULL
GO

UPDATE s SET
	s.EnterpriseUnitRegId = s2.RegId
FROM dbo.StatisticalUnits s
INNER JOIN dbo.StatisticalUnits s2
	ON s.Name = s2.Name
		AND s.ActualAddressId = s2.ActualAddressId
		AND s.AddressId = s2.AddressId
		AND s.Employees = s2.Employees
		AND s2.Discriminator = 'EnterpriseUnit'
WHERE s.Discriminator = 'LegalUnit' AND s.K_PRED IS NOT NULL
GO


/* Units that are not liquidated must not have LiqDate defined
Note: [Statuses] table must have "Liquidated" status with Code = 7 */
