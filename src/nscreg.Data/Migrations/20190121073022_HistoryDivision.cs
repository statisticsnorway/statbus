using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Metadata;

namespace nscreg.Data.Migrations
{
    public partial class HistoryDivision : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
           migrationBuilder.CreateTable(
                name: "EnterpriseGroupsHistory",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    ActualAddressId = table.Column<int>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    ContactPerson = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    DataSourceClassificationId = table.Column<int>(nullable: true),
                    EditComment = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    EmployeesDate = table.Column<DateTime>(nullable: true),
                    EmployeesYear = table.Column<int>(nullable: true),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    EntGroupType = table.Column<string>(nullable: true),
                    ExternalId = table.Column<string>(nullable: true),
                    ExternalIdDate = table.Column<DateTime>(nullable: true),
                    ExternalIdType = table.Column<string>(nullable: true),
                    HistoryEnterpriseUnitIds = table.Column<string>(nullable: true),
                    InstSectorCodeId = table.Column<int>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    LegalFormId = table.Column<int>(nullable: true),
                    LiqDateEnd = table.Column<DateTime>(nullable: true),
                    LiqDateStart = table.Column<DateTime>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(maxLength: 400, nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    NumOfPeopleEmp = table.Column<int>(nullable: true),
                    ParentId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: true),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegMainActivityId = table.Column<int>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReasonId = table.Column<int>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    Size = table.Column<int>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    TelephoneNo = table.Column<string>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    TurnoverDate = table.Column<DateTime>(nullable: true),
                    TurnoverYear = table.Column<int>(nullable: true),
                    UnitStatusId = table.Column<int>(nullable: true),
                    UserId = table.Column<string>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroupsHistory", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_DataSourceClassifications_DataSourceClassificationId",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "StatisticalUnitHistory",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    ActualAddressId = table.Column<int>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    Classified = table.Column<bool>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    DataSourceClassificationId = table.Column<int>(nullable: true),
                    Discriminator = table.Column<string>(nullable: false),
                    EditComment = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    EmployeesDate = table.Column<DateTime>(nullable: true),
                    EmployeesYear = table.Column<int>(nullable: true),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    ExternalId = table.Column<string>(nullable: true),
                    ExternalIdDate = table.Column<DateTime>(nullable: true),
                    ExternalIdType = table.Column<int>(nullable: true),
                    ForeignParticipationCountryId = table.Column<int>(nullable: true),
                    ForeignParticipationId = table.Column<int>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    InstSectorCodeId = table.Column<int>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    LegalFormId = table.Column<int>(nullable: true),
                    LiqDate = table.Column<DateTime>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(maxLength: 400, nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    NumOfPeopleEmp = table.Column<int>(nullable: true),
                    ParentId = table.Column<int>(nullable: true),
                    ParentOrgLink = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: true),
                    RefNo = table.Column<int>(nullable: true),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReasonId = table.Column<int>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<int>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    Size = table.Column<int>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(maxLength: 15, nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: true),
                    SuspensionEnd = table.Column<DateTime>(nullable: true),
                    SuspensionStart = table.Column<DateTime>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    TelephoneNo = table.Column<string>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    TurnoverDate = table.Column<DateTime>(nullable: true),
                    TurnoverYear = table.Column<int>(nullable: true),
                    UnitStatusId = table.Column<int>(nullable: true),
                    UserId = table.Column<string>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true),
                    Commercial = table.Column<bool>(nullable: true),
                    EntGroupId = table.Column<int>(nullable: true),
                    EntGroupIdDate = table.Column<DateTime>(nullable: true),
                    EntGroupRole = table.Column<string>(nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(nullable: true),
                    ForeignCapitalShare = table.Column<string>(nullable: true),
                    HistoryLegalUnitIds = table.Column<string>(nullable: true),
                    MunCapitalShare = table.Column<string>(nullable: true),
                    PrivCapitalShare = table.Column<string>(nullable: true),
                    StateCapitalShare = table.Column<string>(nullable: true),
                    TotalCapital = table.Column<string>(nullable: true),
                    EntRegIdDate = table.Column<DateTime>(nullable: true),
                    EnterpriseUnitRegId = table.Column<int>(nullable: true),
                    HistoryLocalUnitIds = table.Column<string>(nullable: true),
                    Market = table.Column<bool>(nullable: true),
                    LegalUnitId = table.Column<int>(nullable: true),
                    LegalUnitIdDate = table.Column<DateTime>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StatisticalUnitHistory", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_DataSourceClassifications_DataSourceClassificationId",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Countries_ForeignParticipationCountryId",
                        column: x => x.ForeignParticipationCountryId,
                        principalTable: "Countries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_SectorCodes_InstSectorCodeId",
                        column: x => x.InstSectorCodeId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_LegalForms_LegalFormId",
                        column: x => x.LegalFormId,
                        principalTable: "LegalForms",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_StatisticalUnits_ParentId",
                        column: x => x.ParentId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "ActivityStatisticalUnitHistory",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(nullable: false),
                    Activity_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityStatisticalUnitHistory", x => new { x.Unit_Id, x.Activity_Id });
                    table.ForeignKey(
                        name: "FK_ActivityStatisticalUnitHistory_Activities_Activity_Id",
                        column: x => x.Activity_Id,
                        principalTable: "Activities",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id",
                        column: x => x.Unit_Id,
                        principalTable: "StatisticalUnitHistory",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "CountryStatisticalUnitHistory",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(nullable: false),
                    Country_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CountryStatisticalUnitHistory", x => new { x.Unit_Id, x.Country_Id });
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnitHistory_Countries_Country_Id",
                        column: x => x.Country_Id,
                        principalTable: "Countries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id",
                        column: x => x.Unit_Id,
                        principalTable: "StatisticalUnitHistory",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PersonStatisticalUnitHistory",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(nullable: false),
                    Person_Id = table.Column<int>(nullable: false),
                    GroupUnit_Id = table.Column<int>(nullable: true),
                    PersonTypeId = table.Column<int>(nullable: true),
                    StatUnit_Id = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonStatisticalUnitHistory", x => new { x.Unit_Id, x.Person_Id });
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnitHistory_Persons_Person_Id",
                        column: x => x.Person_Id,
                        principalTable: "Persons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnitHistory_PersonTypes_PersonTypeId",
                        column: x => x.PersonTypeId,
                        principalTable: "PersonTypes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id",
                        column: x => x.Unit_Id,
                        principalTable: "StatisticalUnitHistory",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ActivityStatisticalUnitHistory_Activity_Id",
                table: "ActivityStatisticalUnitHistory",
                column: "Activity_Id");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnitHistory_Country_Id",
                table: "CountryStatisticalUnitHistory",
                column: "Country_Id");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_ActualAddressId",
                table: "EnterpriseGroupsHistory",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_AddressId",
                table: "EnterpriseGroupsHistory",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_DataSourceClassificationId",
                table: "EnterpriseGroupsHistory",
                column: "DataSourceClassificationId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_Name",
                table: "EnterpriseGroupsHistory",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_PostalAddressId",
                table: "EnterpriseGroupsHistory",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_RegistrationReasonId",
                table: "EnterpriseGroupsHistory",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_StartPeriod",
                table: "EnterpriseGroupsHistory",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnitHistory_GroupUnit_Id",
                table: "PersonStatisticalUnitHistory",
                column: "GroupUnit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnitHistory_Person_Id",
                table: "PersonStatisticalUnitHistory",
                column: "Person_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnitHistory_StatUnit_Id",
                table: "PersonStatisticalUnitHistory",
                column: "StatUnit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnitHistory_PersonTypeId_Unit_Id_Person_Id",
                table: "PersonStatisticalUnitHistory",
                columns: new[] { "PersonTypeId", "Unit_Id", "Person_Id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_ActualAddressId",
                table: "StatisticalUnitHistory",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_AddressId",
                table: "StatisticalUnitHistory",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_DataSourceClassificationId",
                table: "StatisticalUnitHistory",
                column: "DataSourceClassificationId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_ForeignParticipationCountryId",
                table: "StatisticalUnitHistory",
                column: "ForeignParticipationCountryId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_InstSectorCodeId",
                table: "StatisticalUnitHistory",
                column: "InstSectorCodeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_LegalFormId",
                table: "StatisticalUnitHistory",
                column: "LegalFormId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_Name",
                table: "StatisticalUnitHistory",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_ParentId",
                table: "StatisticalUnitHistory",
                column: "ParentId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_PostalAddressId",
                table: "StatisticalUnitHistory",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_RegistrationReasonId",
                table: "StatisticalUnitHistory",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_StartPeriod",
                table: "StatisticalUnitHistory",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_StatId",
                table: "StatisticalUnitHistory",
                column: "StatId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_EntGroupId",
                table: "StatisticalUnitHistory",
                column: "EntGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_EnterpriseUnitRegId",
                table: "StatisticalUnitHistory",
                column: "EnterpriseUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_LegalUnitId",
                table: "StatisticalUnitHistory",
                column: "LegalUnitId");

            migrationBuilder.Sql(@"
                --DROP FKs
                IF EXISTS (SELECT * 
                  FROM sys.foreign_keys 
                   WHERE object_id = OBJECT_ID(N'dbo.FK_ActivityStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id')
                   AND parent_object_id = OBJECT_ID(N'dbo.ActivityStatisticalUnitHistory')
                )
                  ALTER TABLE [dbo].[ActivityStatisticalUnitHistory] DROP CONSTRAINT [FK_ActivityStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id]
                
                IF EXISTS (SELECT * 
                  FROM sys.foreign_keys 
                   WHERE object_id = OBJECT_ID(N'dbo.FK_CountryStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id')
                   AND parent_object_id = OBJECT_ID(N'dbo.CountryStatisticalUnitHistory')
                )
                  ALTER TABLE [dbo].[CountryStatisticalUnitHistory] DROP CONSTRAINT [FK_CountryStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id]
                
                IF EXISTS (SELECT * 
                  FROM sys.foreign_keys 
                   WHERE object_id = OBJECT_ID(N'dbo.FK_PersonStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id')
                   AND parent_object_id = OBJECT_ID(N'dbo.PersonStatisticalUnitHistory')
                )
                  ALTER TABLE [dbo].[PersonStatisticalUnitHistory] DROP CONSTRAINT [FK_PersonStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id]
                
                
                --MIGRATE RELATIONS
                INSERT dbo.ActivityStatisticalUnitHistory (Unit_Id, Activity_Id)
                SELECT Unit_Id, Activity_Id FROM dbo.ActivityStatisticalUnits WHERE Unit_Id IN (SELECT RegId FROM dbo.StatisticalUnits WHERE ParentId IS NOT NULL)
                
                DELETE dbo.ActivityStatisticalUnits WHERE Unit_Id IN (SELECT RegId FROM dbo.StatisticalUnits WHERE ParentId IS NOT NULL)
                
                INSERT dbo.CountryStatisticalUnitHistory (Unit_Id, Country_Id)
                SELECT Unit_Id, Country_Id FROM dbo.CountryStatisticalUnits WHERE Unit_Id IN (SELECT RegId FROM dbo.StatisticalUnits WHERE ParentId IS NOT NULL)
                
                DELETE dbo.CountryStatisticalUnits WHERE Unit_Id IN (SELECT RegId FROM dbo.StatisticalUnits WHERE ParentId IS NOT NULL)
                
                INSERT dbo.PersonStatisticalUnitHistory (Unit_Id, Person_Id, GroupUnit_Id, PersonTypeId, StatUnit_Id)
                SELECT Unit_Id, Person_Id, GroupUnit_Id, PersonTypeId, StatUnit_Id FROM dbo.PersonStatisticalUnits WHERE Unit_Id IN (SELECT RegId FROM dbo.StatisticalUnits WHERE ParentId IS NOT NULL)
                
                DELETE dbo.PersonStatisticalUnits WHERE Unit_Id IN (SELECT RegId FROM dbo.StatisticalUnits WHERE ParentId IS NOT NULL)
                 
                
                --MIGRATE STATISTICAL_UNITS
                SET IDENTITY_INSERT dbo.StatisticalUnitHistory ON
                
                INSERT dbo.StatisticalUnitHistory
                (
                	RegId,
                    ActualAddressId,
                    AddressId,
                    ChangeReason,
                    Classified,
                    DataSource,
                    DataSourceClassificationId,
                    Discriminator,
                    EditComment,
                    EmailAddress,
                    Employees,
                    EmployeesDate,
                    EmployeesYear,
                    EndPeriod,
                    ExternalId,
                    ExternalIdDate,
                    ExternalIdType,
                    ForeignParticipationCountryId,
                    ForeignParticipationId,
                    FreeEconZone,
                    InstSectorCodeId,
                    IsDeleted,
                    LegalFormId,
                    LiqDate,
                    LiqReason,
                    Name,
                    Notes,
                    NumOfPeopleEmp,
                    ParentId,
                    ParentOrgLink,
                    PostalAddressId,
                    RefNo,
                    RegIdDate,
                    RegistrationDate,
                    RegistrationReasonId,
                    ReorgDate,
                    ReorgReferences,
                    ReorgTypeCode,
                    ReorgTypeId,
                    ShortName,
                    Size,
                    StartPeriod,
                    StatId,
                    StatIdDate,
                    StatusDate,
                    SuspensionEnd,
                    SuspensionStart,
                    TaxRegDate,
                    TaxRegId,
                    TelephoneNo,
                    Turnover,
                    TurnoverDate,
                    TurnoverYear,
                    UnitStatusId,
                    UserId,
                    WebAddress,
                    Commercial,
                    EntGroupId,
                    EntGroupIdDate,
                    EntGroupRole,
                    ForeignCapitalCurrency,
                    ForeignCapitalShare,
                    HistoryLegalUnitIds,
                    MunCapitalShare,
                    PrivCapitalShare,
                    StateCapitalShare,
                    TotalCapital,
                    EntRegIdDate,
                    EnterpriseUnitRegId,
                    HistoryLocalUnitIds,
                    Market,
                    LegalUnitId,
                    LegalUnitIdDate
                )
                SELECT 
                	RegId,
                	ActualAddressId,
                    AddressId,
                    ChangeReason,
                    Classified,
                    DataSource,
                    DataSourceClassificationId,
                    Discriminator + 'History' AS Discriminator,
                    EditComment,
                    EmailAddress,
                    Employees,
                    EmployeesDate,
                    EmployeesYear,
                    EndPeriod,
                    ExternalId,
                    ExternalIdDate,
                    ExternalIdType,
                    ForeignParticipationCountryId,
                    ForeignParticipationId,
                    FreeEconZone,
                    InstSectorCodeId,
                    IsDeleted,
                    LegalFormId,
                    LiqDate,
                    LiqReason,
                    Name,
                    Notes,
                    NumOfPeopleEmp,
                    ParentId,
                    ParentOrgLink,
                    PostalAddressId,
                    RefNo,
                    RegIdDate,
                    RegistrationDate,
                    RegistrationReasonId,
                    ReorgDate,
                    ReorgReferences,
                    ReorgTypeCode,
                    ReorgTypeId,
                    ShortName,
                    Size,
                    StartPeriod,
                    StatId,
                    StatIdDate,
                    StatusDate,
                    SuspensionEnd,
                    SuspensionStart,
                    TaxRegDate,
                    TaxRegId,
                    TelephoneNo,
                    Turnover,
                    TurnoverDate,
                    TurnoverYear,
                    UnitStatusId,
                    UserId,
                    WebAddress,
                    Commercial,
                    EntGroupId,
                    EntGroupIdDate,
                    EntGroupRole,
                    ForeignCapitalCurrency,
                    ForeignCapitalShare,
                    HistoryLegalUnitIds,
                    MunCapitalShare,
                    PrivCapitalShare,
                    StateCapitalShare,
                    TotalCapital,
                    EntRegIdDate,
                    EnterpriseUnitRegId,
                    HistoryLocalUnitIds,
                    Market,
                    LegalUnitId,
                    LegalUnitIdDate
                FROM dbo.StatisticalUnits
                WHERE ParentId IS NOT NULL
                
                SET IDENTITY_INSERT dbo.StatisticalUnitHistory OFF
                
                DELETE dbo.StatisticalUnits WHERE ParentId IS NOT NULL
                
                -- MIGRATE ENTERPRISE_GROUPS
                SET IDENTITY_INSERT dbo.EnterpriseGroupsHistory ON
                
                INSERT dbo.EnterpriseGroupsHistory
                (
                	RegId,
                    ActualAddressId,
                    AddressId,
                    ChangeReason,
                    ContactPerson,
                    DataSource,
                    DataSourceClassificationId,
                    EditComment,
                    EmailAddress,
                    Employees,
                    EmployeesDate,
                    EmployeesYear,
                    EndPeriod,
                    EntGroupType,
                    ExternalId,
                    ExternalIdDate,
                    ExternalIdType,
                    HistoryEnterpriseUnitIds,
                    InstSectorCodeId,
                    IsDeleted,
                    LegalFormId,
                    LiqDateEnd,
                    LiqDateStart,
                    LiqReason,
                    Name,
                    Notes,
                    NumOfPeopleEmp,
                    ParentId,
                    PostalAddressId,
                    RegIdDate,
                    RegMainActivityId,
                    RegistrationDate,
                    RegistrationReasonId,
                    ReorgDate,
                    ReorgReferences,
                    ReorgTypeCode,
                    ReorgTypeId,
                    ShortName,
                    Size,
                    StartPeriod,
                    StatId,
                    StatIdDate,
                    Status,
                    StatusDate,
                    SuspensionEnd,
                    SuspensionStart,
                    TaxRegDate,
                    TaxRegId,
                    TelephoneNo,
                    Turnover,
                    TurnoverDate,
                    TurnoverYear,
                    UnitStatusId,
                    UserId,
                    WebAddress
                )
                SELECT 
                	RegId,
                	ActualAddressId,
                    AddressId,
                    ChangeReason,
                    ContactPerson,
                    DataSource,
                    DataSourceClassificationId,
                    EditComment,
                    EmailAddress,
                    Employees,
                    EmployeesDate,
                    EmployeesYear,
                    EndPeriod,
                    EntGroupType,
                    ExternalId,
                    ExternalIdDate,
                    ExternalIdType,
                    HistoryEnterpriseUnitIds,
                    InstSectorCodeId,
                    IsDeleted,
                    LegalFormId,
                    LiqDateEnd,
                    LiqDateStart,
                    LiqReason,
                    Name,
                    Notes,
                    NumOfPeopleEmp,
                    ParentId,
                    PostalAddressId,
                    RegIdDate,
                    RegMainActivityId,
                    RegistrationDate,
                    RegistrationReasonId,
                    ReorgDate,
                    ReorgReferences,
                    ReorgTypeCode,
                    ReorgTypeId,
                    ShortName,
                    Size,
                    StartPeriod,
                    StatId,
                    StatIdDate,
                    Status,
                    StatusDate,
                    SuspensionEnd,
                    SuspensionStart,
                    TaxRegDate,
                    TaxRegId,
                    TelephoneNo,
                    Turnover,
                    TurnoverDate,
                    TurnoverYear,
                    UnitStatusId,
                    UserId,
                    WebAddress
                FROM dbo.EnterpriseGroups WHERE ParentId IS NOT NULL
                
                SET IDENTITY_INSERT dbo.EnterpriseGroupsHistory OFF
                
                DELETE dbo.EnterpriseGroups WHERE ParentId IS NOT NULL
                
                --RESTORE FKs
                ALTER TABLE dbo.ActivityStatisticalUnitHistory
                ADD CONSTRAINT FK_ActivityStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id
                FOREIGN KEY (Unit_Id) REFERENCES StatisticalUnitHistory(RegId);
                
                ALTER TABLE dbo.CountryStatisticalUnitHistory
                ADD CONSTRAINT FK_CountryStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id
                FOREIGN KEY (Unit_Id) REFERENCES StatisticalUnitHistory(RegId);
                
                ALTER TABLE dbo.PersonStatisticalUnitHistory
                ADD CONSTRAINT FK_PersonStatisticalUnitHistory_StatisticalUnitHistory_Unit_Id
                FOREIGN KEY (Unit_Id) REFERENCES StatisticalUnitHistory(RegId);

            ");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_StatisticalUnits_ParentId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_ParentId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "ParentId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "ParentId",
                table: "EnterpriseGroups");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ActivityStatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "CountryStatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "EnterpriseGroupsHistory");

            migrationBuilder.DropTable(
                name: "PersonStatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "StatisticalUnitHistory");

            migrationBuilder.AddColumn<int>(
                name: "ParentId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ParentId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ParentId",
                table: "StatisticalUnits",
                column: "ParentId");

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_StatisticalUnits_ParentId",
                table: "StatisticalUnits",
                column: "ParentId",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
