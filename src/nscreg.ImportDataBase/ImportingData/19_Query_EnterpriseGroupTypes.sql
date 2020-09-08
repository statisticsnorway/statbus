use KNBS_SBR
go


DELETE FROM [dbo].[EnterpriseGroupTypes]
GO
DBCC CHECKIDENT ('dbo.EnterpriseGroupTypes',RESEED, 1)
GO


insert into EnterpriseGroupTypes (IsDeleted, Name)
values
	(0,	'All-residents'),
	(0,	'Multinational domestically controlled '),
	(0,	'Multinational foreign controlled')
GO
