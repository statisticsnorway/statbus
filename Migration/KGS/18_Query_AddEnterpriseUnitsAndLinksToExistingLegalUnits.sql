INSERT INTO [dbo].[StatisticalUnits]
SELECT	--RegId,
           [ActualAddressId]
           ,[AddressId]
           ,[ChangeReason]
           ,[Classified]
           ,[ContactPerson]
           ,[DataSource]
           ,[DataSourceClassificationId]
           ,'EnterpriseUnit' AS Discriminator
           ,[EditComment]
           ,[EmailAddress]
           ,[Employees]
           ,[EmployeesDate]
           ,[EmployeesYear]
           ,[EndPeriod]
           ,[ExternalId]
           ,[ExternalIdDate]
           ,[ExternalIdType]
           ,[ForeignParticipation]
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
           ,[ParentId]
           ,[ParentOrgLink]
           ,[PostalAddressId]
           ,[RefNo]
           ,[RegIdDate]
           ,[RegistrationDate]
           ,[RegistrationReason]
           ,[ReorgDate]
           ,[ReorgReferences]
           ,[ReorgTypeCode]
           ,[ReorgTypeId]
           ,[ShortName]
           ,[Size]
           ,[StartPeriod]
           ,[StatId]
           ,[StatIdDate]
           ,[StatisticalUnitRegId]
           ,[Status]
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
           ,[RegIdDate]
           ,[EntGroupRole]
           ,[ForeignCapitalCurrency]
           ,[ForeignCapitalShare]
           ,[HistoryLegalUnitIds]
           ,[MunCapitalShare]
           ,[PrivCapitalShare]
           ,[StateCapitalShare]
           ,[TotalCapital]
           ,[RegIdDate]
           ,[EnterpriseUnitRegId]
           ,[Founders]
           ,[HistoryLocalUnitIds]
           ,[Market]
           ,[Owner]
           ,[LegalUnitId]
           ,[LegalUnitIdDate]
		   ,NULL AS [K_PRED]
FROM	dbo.StatisticalUnits
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

INSERT INTO dbo.ActivityStatisticalUnits
SELECT
	EnterpriseUnitRegId,
	Activity_Id 
FROM dbo.StatisticalUnits
	INNER JOIN dbo.ActivityStatisticalUnits
		ON Unit_Id = RegId 
WHERE Discriminator = 'LegalUnit' AND EnterpriseUnitRegId IS NOT NULL 