ALTER TABLE [dbo].[StatisticalUnits]
ADD K_PRED FLOAT NULL
GO

--ALTER TABLE [dbo].[StatisticalUnits] DROP K_PRED

ALTER TABLE [dbo].[StatisticalUnits]
ALTER COLUMN ExternalIdDate DATETIME NULL
GO

ALTER TABLE [dbo].[StatisticalUnits]
ALTER COLUMN RegIdDate DATETIME NULL
GO

DELETE FROM [StatisticalUnits]
GO
DBCC CHECKIDENT ('dbo.StatisticalUnits',RESEED, 1)
GO

DECLARE @guid NVARCHAR(450)
SELECT @guid = Id FROM [dbo].[AspNetUsers]

INSERT INTO [dbo].[StatisticalUnits]
    ([ActualAddressId], [AddressId], [ChangeReason], [ContactPerson], [DataSource], [DataSourceClassificationId], [Discriminator], [EditComment], [EmailAddress]
    , [Employees], [EmployeesDate], [EmployeesYear], [EndPeriod], [ExternalId], [ExternalIdDate], [ExternalIdType], [ForeignParticipationCountryId]
    , [ForeignParticipationId], [InstSectorCodeId], [IsDeleted], [LegalFormId], [LiqDate], [LiqReason], [Name], [Notes], [NumOfPeopleEmp], [ParentId]
    , [ParentOrgLink], [PostalAddressId], [RefNo], [RegIdDate], [RegistrationDate], [RegistrationReason], [ReorgDate], [ReorgReferences]
    , [ReorgTypeCode], [ReorgTypeId], [ShortName], [Size], [StartPeriod], [StatId], [StatIdDate], [Status], [StatusDate], [SuspensionEnd], [SuspensionStart]
    , [TaxRegDate], [TaxRegId], [TelephoneNo], [Turnover], [TurnoverDate], [TurnoverYear], [UnitStatusId], [UserId], [WebAddress], [Classified], [Commercial]
    , [EntGroupId], [EntGroupIdDate], [EntGroupRole], [ForeignCapitalCurrency], [ForeignCapitalShare], [ForeignParticipation], [FreeEconZone], [MunCapitalShare], [PrivCapitalShare]
	, [StateCapitalShare], [TotalCapital], [EntRegIdDate], [EnterpriseUnitRegId], [Founders], [Market], [Owner], [LegalUnitId], [LegalUnitIdDate], [K_PRED])
SELECT 
	a.Address_id AS ActualAddressId,
	a.Address_id AS AddressId,
	0 AS ChangeReason,
    '' AS ContactPerson,
    '' AS DataSource,
    NULL AS DataSourceClassificationId, 
    CASE
		WHEN K_PME = 0 THEN 'LegalUnit'
		ELSE 'LocalUnit'
	END AS Discriminator,
	'' AS EditComment,
	E_MAIL AS EmailAddress, 
	S_SPR1 AS Employees,
	GETDATE() AS EmployeesDate,
	2017 AS EmployeesYear,
    '9999-12-31 23:59:59.9999999' AS EndPeriod,
	REG_J AS ExternalId ,		
	D_R_J AS ExternalIdDate,
	0 AS ExternalIdType,
    NULL AS ForeignParticipationCountryId,
    fp.Id AS ForeignParticipationId,
    s.Id AS InstSectorCodeId,
	0 AS IsDeleted,
	l.Id AS LegalFormId,
    '' AS LiqDate,
	'' AS LiqReason,
	NAME_S AS Name,
	'' AS Notes,
	S_SPR1 AS NumOfPeopleEmp,
	NULL AS ParentId,
	NULL as ParentOrgLink,
	INDEXF AS PostalAddressId,
    0 AS RefNo,
	ISNULL(D_VVOD, GETDATE()) AS RegIdDate,
	GETDATE() AS RegistrationDate,
	'' AS RegistrationReason,
	GETDATE() AS ReorgDate,
	'' AS ReorgReferences,
	'' AS ReorgTypeCode,
    NULL AS ReorgTypeId,
    '' AS ShortName,
    NULL AS Size,
    GETDATE() AS StartPeriod,
	k.K_PRED AS StatId,
	GETDATE() AS StatIdDate,
	L_PRI AS [Status],
	GETDATE() AS StatusDate,
	DVD AS SuspensionEnd,
	DPD AS SuspensionStart,
    GETDATE() AS TaxRegDate,
	K_SOC AS TaxRegId,
	ISNULL(T_ON + ', ', '') + ISNULL(T_FAKS, '') AS TelephoneNo,
    V_PRI AS Turnover,
    GETDATE() AS TurnoverDate,
    2017 AS TurnoverYear,
    NULL AS UnitStatusId,
    @guid AS UserId,
	'' AS WebAddress,
    '' AS Classified,
    CASE
		WHEN V_DE = 0 OR V_DE = 1 THEN 0
		ELSE 1
	END AS Commercial,
	NULL AS EntGroupId,
	NULL AS EntGroupIdDate,
	'' AS EntGroupRole,
    '' AS ForeignCapitalCurrency,
	'' AS ForeignCapitalShare,
	CASE 
		WHEN fp.Id IS NOT NULL THEN 'yes'
		ELSE 'no'
	END AS ForeignParticipation, --need to think what we will do. we have ForeignParticipationId as reference
	SEZ AS FreeEconZone,
	'' AS MunCapitalShare,
	'' AS PrivCapitalShare,
	'' AS StateCapitalShare,
    USTV AS TotalCapital,
	NULL AS EntRegIdDate,
    NULL AS EnterpriseUnitRegId,
	'' AS Founders,
	CASE
		WHEN V_DE = 0 OR V_DE = 1 THEN 0
		ELSE 1
	END AS Market,
	'' AS Owner,
	NULL AS LegalUnitId,
	GETDATE() AS LegalUnitIdDate,
	k.K_PRED AS K_PRED
FROM [statcom].[dbo].[KATME] AS k
INNER JOIN [dbo].[Address] AS a
	ON a.K_PRED = k.K_PRED
LEFT JOIN [dbo].[SectorCodes] s
	ON s.Code = k.SEK_EK
LEFT JOIN [dbo].[LegalForms] l
	ON CAST(LEFT(k.KTP,2) AS INT) = l.Code
LEFT JOIN [dbo].[ForeignParticipations] fp
	ON fp.Id = SUBSTRING(CAST(KTP AS VARCHAR(100)), 4, 1)
--LEFT JOIN [dbo].[PostalIndices] p
--	ON p.Name = k.[INDEXF]
GO
	



