use KNBS_SBR
go

DELETE FROM [EnterpriseGroupRoles]
GO
DBCC CHECKIDENT ('dbo.EnterpriseGroupRoles',RESEED, 1)
GO

insert into EnterpriseGroupRoles (Name, IsDeleted, Code)
values
('Management/control unit', 0, 1),
('Global group head (controlling unit)', 0, 2),
('Global decision centre (managing unit)', 0, 3),
('Highest level consolidation unit', 0, 4),
('Other', 0, 5)
GO