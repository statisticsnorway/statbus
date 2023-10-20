using Microsoft.EntityFrameworkCore;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public class MsSqlDbInitializer : IDbInitializer
    {
        [System.Obsolete]
        public void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null)
        {
            #region Scripts

            const string dropStatUnitSearchViewTable =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE V_StatUnitSearch
                """;


            const string dropStatUnitSearchView =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch'  AND TABLE_TYPE = 'VIEW')
                DROP VIEW [dbo].[V_StatUnitSearch]
                """;


            const string createStatUnitSearchView =
                """
                CREATE VIEW [dbo].[V_StatUnitSearch]
                AS
                SELECT
                    RegId,
                    Name,
                    TaxRegId,
                    StatId,
                    ExternalId,
                    act_addr.Region_id AS ActualAddressRegionId,
                    Employees,
                    Turnover,
                    InstSectorCodeId AS SectorCodeId,
                    LegalFormId,
                    DataSourceClassificationId,
                    ChangeReason,
                    StartPeriod,
                    IsDeleted,
                    LiqReason,
                    LiqDate,               
                    act_addr.Address_id AS ActualAddressId,
                    act_addr.Address_part1 AS ActualAddressPart1,
                    act_addr.Address_part2 AS ActualAddressPart2,
                    act_addr.Address_part3 AS ActualAddressPart3,
                    CASE
                        WHEN Discriminator = 'LocalUnit' THEN 1
                        WHEN Discriminator = 'LegalUnit' THEN 2
                        WHEN Discriminator = 'EnterpriseUnit' THEN 3
                    END
                    AS UnitType
                FROM	StatisticalUnits                   
                    LEFT JOIN Address as act_addr
                        ON ActualAddressId = act_addr.Address_id

                UNION ALL

                SELECT
                    RegId,
                    Name,
                    TaxRegId,
                    StatId,
                    ExternalId,
                    act_addr.Region_id AS ActualAddressRegionId,
                    Employees,
                    Turnover,
                    NULL AS SectorCodeId,
                    NULL AS LegalFormId,
                    DataSourceClassificationId,
                    ChangeReason,
                    StartPeriod,
                    IsDeleted,
                    LiqReason,
                    LiqDateEnd,
                    act_addr.Address_id AS ActualAddressId,
                    act_addr.Address_part1 AS ActualAddressPart1,
                    act_addr.Address_part2 AS ActualAddressPart2,
                    act_addr.Address_part3 AS ActualAddressPart3,
                    4 AS UnitType
                FROM	EnterpriseGroups
                    LEFT JOIN Address as act_addr
                        ON ActualAddressId = act_addr.Address_id;

                """;


            const string dropReportTreeTable =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ReportTree' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE ReportTree
                """;


            const string dropProcedureGetReportsTree =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetReportsTree' AND ROUTINE_TYPE = 'PROCEDURE')
                DROP PROCEDURE GetReportsTree
                """;


            string createProcedureGetReportsTree =
                $"""
                CREATE PROCEDURE GetReportsTree
                    @user NVARCHAR(100)
                AS
                BEGIN
                    DECLARE @ReportTree TABLE
                    (
                        Id INT,
                        Title NVARCHAR(500) NULL,
                        Type NVARCHAR(100) NULL,
                        ReportId INT NULL,
                        ParentNodeId INT NULL,
                        IsDeleted BIT NULL,
                        ResourceGroup NVARCHAR(100) NULL,
                        ReportUrl NVARCHAR(MAX) NULL DEFAULT ''
                    )

                    DECLARE @query NVARCHAR(1000) = N'SELECT *
                        FROM OPENQUERY({reportingSettings?.LinkedServerName},
                        ''SELECT
                            Id,
                            Title,
                            Type,
                            ReportId,
                            ParentNodeId,
                            IsDeleted,
                            ResourceGroup,
                            NULL as ReportUrl
                        From ReportTreeNode rtn
                        Where rtn.IsDeleted = 0
                            And (rtn.ReportId is null or rtn.ReportId in (Select distinct ReportId From ReportAce where Principal = ''''' +@user+'''''))'');';

                    INSERT @ReportTree EXEC (@query)

                    SELECT * FROM @ReportTree
                END
                """;


            const string dropFunctionGetActivityChildren =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetActivityChildren' AND ROUTINE_TYPE = 'FUNCTION')
                DROP FUNCTION GetActivityChildren
                """;


            const string createFunctionGetActivityChildren =
                """
                CREATE FUNCTION [dbo].[GetActivityChildren]
                (
                	@activityId INT,
                    @activitiesIds NVARCHAR(max)
                )
                RETURNS TABLE
                AS
                RETURN
                (
                	  WITH ActivityCte ([Id], [Code], [DicParentId], [IsDeleted], [Name], [NameLanguage1], [NameLanguage2], [ParentId], [Section], [VersionId], [ActivityCategoryLevel]) AS
                	  (
                		SELECT
                		   [Id]
                		  ,[Code]
                		  ,[DicParentId]
                		  ,[IsDeleted]
                		  ,[Name]
                          ,[NameLanguage1]
                          ,[NameLanguage2]
                		  ,[ParentId]
                		  ,[Section]
                		  ,[VersionId]
                          ,[ActivityCategoryLevel]
                		FROM [dbo].[ActivityCategories]
                		WHERE CONCAT(',', @activitiesIds, ',') LIKE CONCAT('%,',[Id], ',%') OR [Id] = @activityId

                		UNION ALL

                		SELECT
                		   ac.[Id]
                		  ,ac.[Code]
                		  ,ac.[DicParentId]
                		  ,ac.[IsDeleted]
                		  ,ac.[Name]
                          ,ac.[NameLanguage1]
                          ,ac.[NameLanguage2]
                		  ,ac.[ParentId]
                		  ,ac.[Section]
                		  ,ac.[VersionId]
                          ,ac.[ActivityCategoryLevel]
                		FROM [dbo].[ActivityCategories] ac
                			INNER JOIN ActivityCte
                			ON ActivityCte.[Id] = ac.[ParentId]
                	)

                	SELECT * FROM ActivityCte
                )
                """;


            const string dropFunctionGetRegionChildren =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetRegionChildren' AND ROUTINE_TYPE = 'FUNCTION')
                DROP FUNCTION GetRegionChildren
                """;


            const string createFunctionGetRegionChildren =
                """
                CREATE FUNCTION [dbo].[GetRegionChildren]
                (
                	@regionId INT
                )
                RETURNS TABLE
                AS
                RETURN
                (
                	 WITH RegionsCte ([Id], [AdminstrativeCenter], [Code], [IsDeleted], [Name], [NameLanguage1], [NameLanguage2], [ParentId], [FullPath], [FullPathLanguage1], [FullPathLanguage2], [RegionLevel]) AS
                	  (
                		SELECT
                		   [Id]
                		  ,[AdminstrativeCenter]
                		  ,[Code]
                		  ,[IsDeleted]
                		  ,[Name]
                          ,[NameLanguage1]
                          ,[NameLanguage2]
                		  ,[ParentId]
                		  ,[FullPath]
                          ,[FullPathLanguage1]
                          ,[FullPathLanguage2]
                          ,[RegionLevel]
                		FROM [dbo].[Regions]
                		WHERE [Id] = @regionId

                		UNION ALL

                		SELECT
                		   r.[Id]
                		  ,r.[AdminstrativeCenter]
                		  ,r.[Code]
                		  ,r.[IsDeleted]
                		  ,r.[Name]
                          ,r.[NameLanguage1]
                          ,r.[NameLanguage2]
                		  ,r.[ParentId]
                		  ,r.[FullPath]
                          ,r.[FullPathLanguage1]
                          ,r.[FullPathLanguage2]
                          ,r.[RegionLevel]
                		FROM [dbo].[Regions] r
                			INNER JOIN RegionsCte rc
                			ON rc.[Id] = r.[ParentId]

                	  )

                	 SELECT * FROM RegionsCte
                )
                """;


            const string dropFunctionGetRegionParent =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetRegionParent' AND ROUTINE_TYPE = 'FUNCTION')
                DROP FUNCTION GetRegionParent
                """;


            const string createFunctionGetRegionParent =
                """
                CREATE FUNCTION [dbo].[GetRegionParent]
                (
                	@regionid INT,
                    @level TINYINT
                )
                RETURNS INT
                AS
                BEGIN
                    DECLARE @res int;

                	WITH region_tree as
                	(
                	SELECT id, parentid, 0 as lvl
                	FROM [dbo].[regions]
                	WHERE id = @regionid
                		UNION ALL
                	SELECT r.id, r.parentid, lvl + 1
                	FROM region_tree p, [dbo].[regions] r
                	WHERE p.parentid = r.id
                	),

                	region_tree_levels as
                		(
                			SELECT row_number() over (order by lvl desc) as [level],
                			region_tree.*
                			FROM region_tree
                    )

                	 SELECT @res = id
                	 FROM region_tree_levels
                	 WHERE [level] = @level

                	    RETURN @res
                    END
                """;


            const string dropFunctionGetActivityParent =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetActivityParent' AND ROUTINE_TYPE = 'FUNCTION')
                DROP FUNCTION GetActivityParent
                """;


            const string createFunctionGetActivityParent =
                """
                CREATE FUNCTION [dbo].[GetActivityParent]
                (
                	@activity_id INT,
                    @level TINYINT,
                    @param_name	NVARCHAR(50)
                )
                RETURNS NVARCHAR(2000)
                AS
                BEGIN
                    DECLARE @res NVARCHAR(2000);

                	WITH
                    activity_tree as
                	(
                	SELECT id, parentid, 0 as lvl, Code, [Name]
                	FROM [dbo].[ActivityCategories]
                	WHERE id = @activity_id
                		UNION ALL
                	SELECT ac.id, ac.parentid, tr.lvl + 1, ac.Code, ac.[Name]
                	FROM activity_tree tr, [dbo].[ActivityCategories] ac
                	WHERE tr.parentid = ac.id
                	),

                	activity_levels as
                		(
                			SELECT row_number() over (order by lvl desc) as [level],
                			tr.*
                			FROM activity_tree tr
                        )

                	        SELECT @res =
                                CASE LOWER(@param_name)
                            WHEN 'code' THEN [Code]
                            WHEN 'name' THEN [Name]
                            END
                	        FROM activity_levels
                	        WHERE [level] = @level

                	    RETURN @res
                    END
                """;


            const string dropFunctionGetSectorParent =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetSectorParent' AND ROUTINE_TYPE = 'FUNCTION')
                DROP FUNCTION GetSectorParent
                """;


            const string createFunctionGetSectorParent =
                """
                CREATE FUNCTION [dbo].[GetSectorParent]
                (
                	@sector_id INT,
                    @level TINYINT,
                    @param_name	NVARCHAR(50)
                )
                RETURNS NVARCHAR(2000)
                AS
                BEGIN
                    DECLARE @res NVARCHAR(2000);

                	WITH
                    sector_tree as
                	(
                	SELECT id, parentid, 0 as lvl, Code, [Name]
                	FROM [dbo].[SectorCodes] sc
                	WHERE id = @sector_id
                		UNION ALL
                	SELECT sc.id, sc.parentid, tr.lvl + 1, sc.Code, sc.[Name]
                	FROM sector_tree tr, [dbo].[SectorCodes] sc
                	WHERE tr.parentid = sc.id
                	),

                	sector_levels as
                		(
                			SELECT row_number() over (order by lvl desc) as [level],
                			tr.*
                			FROM sector_tree tr
                        )

                	        SELECT @res =
                                CASE LOWER(@param_name)
                            WHEN 'code' THEN [Code]
                            WHEN 'name' THEN [Name]
                            END
                	        FROM sector_levels
                	        WHERE [level] = @level

                	    RETURN @res
                    END
                """;


            const string dropStatUnitEnterpriseViewTable =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitEnterprise_2021' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE V_StatUnitEnterprise_2021
                """;


            const string dropStatUnitEnterpriseTable =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitEnterprise_2021'  AND TABLE_TYPE = 'VIEW')
                DROP VIEW [dbo].[V_StatUnitEnterprise_2021]
                """;


            const string createStatUnitEnterpriseView =
                """
                CREATE view [dbo].[V_StatUnitEnterprise_2021]
                as
                    select
                	    stu.StatId,
                	    isnull([dbo].GetRegionParent(adr.Region_id,1) ,adr.Region_id) Oblast,
                	    isnull([dbo].GetRegionParent(adr.Region_id,2) ,adr.Region_id) Rayon,
                	    dbo.GetActivityParent(acg.Id,1,'code') ActCat_section_code,
                	    dbo.GetActivityParent(acg.Id,1,'name') ActCat_section_desc,
                	    dbo.GetActivityParent(acg.Id,2,'code') ActCat_2dig_code,
                	    dbo.GetActivityParent(acg.Id,2,'name') ActCat_2dig_desc,
                	    dbo.GetActivityParent(acg.Id,3,'code') ActCat_3dig_code,
                	    dbo.GetActivityParent(acg.Id,3,'name') ActCat_3dig_desc,
                	    lfm.Code LegalForm_code,
                	    lfm.Name LegalForm_desc,
                	    dbo.GetSectorParent(stu.InstSectorCodeId,1,'code') InstSectorCode_level1,
                	    dbo.GetSectorParent(stu.InstSectorCodeId,1,'name') InstSectorCode_level1_desc,
                	    dbo.GetSectorParent(stu.InstSectorCodeId,2,'code') InstSectorCode_level2,
                	    dbo.GetSectorParent(stu.InstSectorCodeId,2,'name') InstSectorCode_level2_desc,
                	    uns.Code SizeCode,
                	    uns.Name SizeDesc,
                	    iif((stu.TurnoverYear = year(getdate()) -1
                                or year(stu.TurnoverDate) = year(getdate()) -1),stu.Turnover, null) Turnover,
                	    iif((stu.EmployeesYear = year(getdate()) -1
                                or year(stu.EmployeesDate) = year(getdate()) -1), act.Employees, null) Employees,
                	    iif((stu.EmployeesYear = year(getdate()) -1
                			    or year(stu.EmployeesDate) = year(getdate()) -1), stu.NumOfPeopleEmp, null) NumOfPeopleEmp,
                	    stu.RegistrationDate,
                	    stu.LiqDate,
                	    sts.Code StatusCode,
                	    sts.Name StatusDesc,
                	    psn.Sex
                    from
                	    dbo.StatisticalUnits stu
                	    left join dbo.Address aad on stu.ActualAddressId = aad.Address_id
                	    left join dbo.ActivityStatisticalUnits asu on stu.RegId = asu.Unit_Id
                	    left join dbo.Activities act on asu.Activity_Id = act.Id
                	    left join dbo.ActivityCategories acg on act.ActivityCategoryId = acg.Id
                	    left join dbo.LegalForms lfm on stu.LegalFormId = lfm.Id
                	    left join dbo.UnitsSize uns on stu.SizeId = uns.Id
                	    left join dbo.PersonStatisticalUnits psu on stu.RegId = psu.Unit_Id and psu.PersonTypeId = 3 --manager
                	    left join dbo.Persons psn on psu.Person_Id = psn.Id
                	    left join dbo.Statuses sts on stu.UnitStatusId = sts.Id

                    where
                	    lower(stu.Discriminator) = 'enterpriseunit'
                """;


            const string dropStatUnitLocalViewTable =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitLocal_2021' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE V_StatUnitLocal_2021
                """;


            const string dropStatUnitLocalTable =
                """
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitLocal_2021'  AND TABLE_TYPE = 'VIEW')
                DROP VIEW [dbo].[V_StatUnitLocal_2021]
                """;


            const string createStatUnitLocalView =
                """
                CREATE view [dbo].[V_StatUnitLocal_2021]
                as
                    select
                	    stu.StatId,
                	    isnull(dbo.GetRegionParent(adr.Region_id,1)
                		    ,adr.Region_id) Oblast,
                	    isnull(dbo.GetRegionParent(adr.Region_id,2)
                		    ,adr.Region_id) Rayon,
                    dbo.GetActivityParent(acg.Id,1,'code') ActCat_section_code,
                    dbo.GetActivityParent(acg.Id,1,'name') ActCat_section_desc,
                    dbo.GetActivityParent(acg.Id,2,'code') ActCat_2dig_code,
                    dbo.GetActivityParent(acg.Id,2,'name') ActCat_2dig_desc,
                    dbo.GetActivityParent(acg.Id,3,'code') ActCat_3dig_code,
                    dbo.GetActivityParent(acg.Id,3,'name') ActCat_3dig_desc,
                    lfm.Code LegalForm_code,
                    lfm.Name LegalForm_desc,
                    dbo.GetSectorParent(stu.InstSectorCodeId,1,'code') InstSectorCode_level1,
                    dbo.GetSectorParent(stu.InstSectorCodeId,1,'name') InstSectorCode_level1_desc,
                    dbo.GetSectorParent(stu.InstSectorCodeId,2,'code') InstSectorCode_level2,
                    dbo.GetSectorParent(stu.InstSectorCodeId,2,'name') InstSectorCode_level2_desc,
                    uns.Code SizeCode,
                    uns.Name SizeDesc,
                    iif((stu.TurnoverYear = year(getdate()) -1
                		    or year(stu.TurnoverDate) = year(getdate()) -1
                		    ),stu.Turnover, null) Turnover,
                    iif((stu.EmployeesYear = year(getdate()) -1
                		    or year(stu.EmployeesDate) = year(getdate()) -1
                		    ), act.Employees, null) Employees,
                    iif((stu.EmployeesYear = year(getdate()) -1
                		    or year(stu.EmployeesDate) = year(getdate()) -1
                		    ), stu.NumOfPeopleEmp, null) NumOfPeopleEmp,
                    stu.RegistrationDate,
                    stu.LiqDate,
                    sts.Code StatusCode,
                    sts.Name StatusDesc,
                    psn.Sex
                from
                    dbo.StatisticalUnits stu
                    left join dbo.Address aad on stu.ActualAddressId = aad.Address_id
                    left join dbo.ActivityStatisticalUnits asu on stu.RegId = asu.Unit_Id
                    left join dbo.Activities act on asu.Activity_Id = act.Id
                    left join dbo.ActivityCategories acg on act.ActivityCategoryId = acg.Id
                    left join dbo.LegalForms lfm on stu.LegalFormId = lfm.Id
                    left join dbo.UnitsSize uns on stu.SizeId = uns.Id
                    left join dbo.PersonStatisticalUnits psu on stu.RegId = psu.Unit_Id and psu.PersonTypeId = 3 --manager
                    left join dbo.Persons psn on psu.Person_Id = psn.Id
                    left join dbo.Statuses sts on stu.UnitStatusId = sts.Id

                where
                    lower(stu.Discriminator) = 'localunit'
                """;

            #endregion

            context.Database.ExecuteSqlRaw(dropStatUnitSearchViewTable);
            context.Database.ExecuteSqlRaw(dropStatUnitSearchView);
            context.Database.ExecuteSqlRaw(createStatUnitSearchView);

            context.Database.ExecuteSqlRaw(dropReportTreeTable);
            context.Database.ExecuteSqlRaw(dropProcedureGetReportsTree);
#pragma warning disable EF1000 // Possible SQL injection vulnerability.
            context.Database.ExecuteSqlRaw(createProcedureGetReportsTree);
#pragma warning restore EF1000 // Possible SQL injection vulnerability.

            context.Database.ExecuteSqlRaw(dropFunctionGetActivityChildren);
            context.Database.ExecuteSqlRaw(createFunctionGetActivityChildren);

            context.Database.ExecuteSqlRaw(dropFunctionGetRegionChildren);
            context.Database.ExecuteSqlRaw(createFunctionGetRegionChildren);

            context.Database.ExecuteSqlRaw(dropStatUnitEnterpriseViewTable);
            context.Database.ExecuteSqlRaw(dropStatUnitEnterpriseTable);
            context.Database.ExecuteSqlRaw(createStatUnitEnterpriseView);

            context.Database.ExecuteSqlRaw(dropFunctionGetRegionParent);
            context.Database.ExecuteSqlRaw(createFunctionGetRegionParent);

            context.Database.ExecuteSqlRaw(dropFunctionGetActivityParent);
            context.Database.ExecuteSqlRaw(createFunctionGetActivityParent);

            context.Database.ExecuteSqlRaw(dropFunctionGetSectorParent);
            context.Database.ExecuteSqlRaw(createFunctionGetSectorParent);

            context.Database.ExecuteSqlRaw(dropStatUnitLocalViewTable);
            context.Database.ExecuteSqlRaw(dropStatUnitLocalTable);
            context.Database.ExecuteSqlRaw(createStatUnitLocalView);
        }
    }
}
