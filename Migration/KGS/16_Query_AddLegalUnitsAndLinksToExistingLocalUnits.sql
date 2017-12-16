INSERT INTO [dbo].[StatisticalUnits]
SELECT
           [ActualAddressId]
           ,[AddressId]
           ,[ChangeReason]
           ,[Classified]
           ,[ContactPerson]
           ,[DataSource]
           ,[DataSourceClassificationId]
           ,'LegalUnit' AS Discriminator
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
           ,[Founders]
           ,[HistoryLocalUnitIds]
           ,[Market]
           ,[Owner]
           ,[LegalUnitId]
           ,[LegalUnitIdDate]
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

INSERT INTO dbo.ActivityStatisticalUnits
SELECT
	LegalUnitId,
	Activity_Id 
FROM dbo.StatisticalUnits
	INNER JOIN dbo.ActivityStatisticalUnits
		ON Unit_Id = RegId 
WHERE Discriminator = 'LocalUnit' AND LegalUnitId IS NOT NULL


