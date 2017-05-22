using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Metadata;

namespace nscreg.data.Migrations
{
    public partial class Initial : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AspNetUserTokens",
                columns: table => new
                {
                    UserId = table.Column<string>(nullable: false),
                    LoginProvider = table.Column<string>(nullable: false),
                    Name = table.Column<string>(nullable: false),
                    Value = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUserTokens", x => new { x.UserId, x.LoginProvider, x.Name });
                });

            migrationBuilder.CreateTable(
                name: "ActivityCategories",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    Code = table.Column<string>(maxLength: 10, nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: false),
                    Section = table.Column<string>(maxLength: 10, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategories", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Address",
                columns: table => new
                {
                    Address_id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    AddressDetails = table.Column<string>(nullable: true),
                    Address_part1 = table.Column<string>(nullable: true),
                    Address_part2 = table.Column<string>(nullable: true),
                    Address_part3 = table.Column<string>(nullable: true),
                    Address_part4 = table.Column<string>(nullable: true),
                    Address_part5 = table.Column<string>(nullable: true),
                    Geographical_codes = table.Column<string>(nullable: true),
                    GPS_coordinates = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Address", x => x.Address_id);
                });

            migrationBuilder.CreateTable(
                name: "Regions",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    Name = table.Column<string>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Regions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoles",
                columns: table => new
                {
                    Id = table.Column<string>(nullable: false),
                    AccessToSystemFunctions = table.Column<string>(nullable: true),
                    ConcurrencyStamp = table.Column<string>(nullable: true),
                    Description = table.Column<string>(nullable: true),
                    Name = table.Column<string>(maxLength: 256, nullable: true),
                    NormalizedName = table.Column<string>(maxLength: 256, nullable: true),
                    StandardDataAccess = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetRoles", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Soates",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    AdminstrativeCenter = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    Name = table.Column<string>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Soates", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseGroups",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    ActualAddressId = table.Column<int>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    ContactPerson = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    EditComment = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: false),
                    EmployeesDate = table.Column<DateTime>(nullable: false),
                    EmployeesFte = table.Column<int>(nullable: false),
                    EmployeesYear = table.Column<DateTime>(nullable: false),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    EntGroupType = table.Column<string>(nullable: true),
                    ExternalId = table.Column<int>(nullable: false),
                    ExternalIdDate = table.Column<DateTime>(nullable: false),
                    ExternalIdType = table.Column<int>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false),
                    LiqDateEnd = table.Column<DateTime>(nullable: false),
                    LiqDateStart = table.Column<DateTime>(nullable: false),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    ParrentId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: false),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: false),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: false),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: false),
                    TaxRegId = table.Column<int>(nullable: false),
                    TelephoneNo = table.Column<string>(nullable: true),
                    TurnoveDate = table.Column<DateTime>(nullable: false),
                    Turnover = table.Column<decimal>(nullable: false),
                    TurnoverYear = table.Column<DateTime>(nullable: false),
                    UserId = table.Column<string>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroups", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_EnterpriseGroups_ParrentId",
                        column: x => x.ParrentId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUsers",
                columns: table => new
                {
                    Id = table.Column<string>(nullable: false),
                    AccessFailedCount = table.Column<int>(nullable: false),
                    ConcurrencyStamp = table.Column<string>(nullable: true),
                    CreationDate = table.Column<DateTime>(nullable: false),
                    DataAccess = table.Column<string>(nullable: true),
                    Description = table.Column<string>(nullable: true),
                    Email = table.Column<string>(maxLength: 256, nullable: true),
                    EmailConfirmed = table.Column<bool>(nullable: false),
                    LockoutEnabled = table.Column<bool>(nullable: false),
                    LockoutEnd = table.Column<DateTimeOffset>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    NormalizedEmail = table.Column<string>(maxLength: 256, nullable: true),
                    NormalizedUserName = table.Column<string>(maxLength: 256, nullable: true),
                    PasswordHash = table.Column<string>(nullable: true),
                    PhoneNumber = table.Column<string>(nullable: true),
                    PhoneNumberConfirmed = table.Column<bool>(nullable: false),
                    RegionId = table.Column<int>(nullable: true),
                    SecurityStamp = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    SuspensionDate = table.Column<DateTime>(nullable: true),
                    TwoFactorEnabled = table.Column<bool>(nullable: false),
                    UserName = table.Column<string>(maxLength: 256, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUsers", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AspNetUsers_Regions_RegionId",
                        column: x => x.RegionId,
                        principalTable: "Regions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoleClaims",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    ClaimType = table.Column<string>(nullable: true),
                    ClaimValue = table.Column<string>(nullable: true),
                    RoleId = table.Column<string>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetRoleClaims", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AspNetRoleClaims_AspNetRoles_RoleId",
                        column: x => x.RoleId,
                        principalTable: "AspNetRoles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserClaims",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    ClaimType = table.Column<string>(nullable: true),
                    ClaimValue = table.Column<string>(nullable: true),
                    UserId = table.Column<string>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUserClaims", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AspNetUserClaims_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserLogins",
                columns: table => new
                {
                    LoginProvider = table.Column<string>(nullable: false),
                    ProviderKey = table.Column<string>(nullable: false),
                    ProviderDisplayName = table.Column<string>(nullable: true),
                    UserId = table.Column<string>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUserLogins", x => new { x.LoginProvider, x.ProviderKey });
                    table.ForeignKey(
                        name: "FK_AspNetUserLogins_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserRoles",
                columns: table => new
                {
                    UserId = table.Column<string>(nullable: false),
                    RoleId = table.Column<string>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUserRoles", x => new { x.UserId, x.RoleId });
                    table.ForeignKey(
                        name: "FK_AspNetUserRoles_AspNetRoles_RoleId",
                        column: x => x.RoleId,
                        principalTable: "AspNetRoles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_AspNetUserRoles_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Activities",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    Activity_Revx = table.Column<int>(nullable: false),
                    Activity_Revy = table.Column<int>(nullable: false),
                    Activity_Type = table.Column<int>(nullable: false),
                    Activity_Year = table.Column<int>(nullable: false),
                    Employees = table.Column<int>(nullable: false),
                    Id_Date = table.Column<DateTime>(nullable: false),
                    Turnover = table.Column<decimal>(nullable: false),
                    Updated_By = table.Column<string>(nullable: false),
                    Updated_Date = table.Column<DateTime>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Activities", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Activities_ActivityCategories_Activity_Revx",
                        column: x => x.Activity_Revx,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_Activities_AspNetUsers_Updated_By",
                        column: x => x.Updated_By,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "DataSources",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    AllowedOperations = table.Column<int>(nullable: false),
                    AttributesToCheck = table.Column<string>(nullable: true),
                    Description = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: false),
                    Priority = table.Column<int>(nullable: false),
                    Restrictions = table.Column<string>(nullable: true),
                    StatUnitType = table.Column<int>(nullable: false),
                    UserId = table.Column<string>(nullable: true),
                    VariablesMapping = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSources", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DataSources_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "StatisticalUnits",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    ActualAddressId = table.Column<int>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    Classified = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    Discriminator = table.Column<string>(nullable: false),
                    EditComment = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: false),
                    EmployeesDate = table.Column<DateTime>(nullable: false),
                    EmployeesYear = table.Column<DateTime>(nullable: false),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    ExternalId = table.Column<int>(nullable: false),
                    ExternalIdDate = table.Column<DateTime>(nullable: false),
                    ExternalIdType = table.Column<int>(nullable: false),
                    ForeignParticipation = table.Column<string>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false),
                    LiqDate = table.Column<string>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    NumOfPeople = table.Column<int>(nullable: false),
                    ParrentId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: false),
                    RefNo = table.Column<int>(nullable: false),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegMainActivityId = table.Column<int>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: false),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(maxLength: 15, nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: false),
                    Status = table.Column<int>(nullable: false),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: false),
                    TaxRegId = table.Column<int>(nullable: false),
                    TelephoneNo = table.Column<string>(nullable: true),
                    TurnoveDate = table.Column<DateTime>(nullable: false),
                    Turnover = table.Column<decimal>(nullable: false),
                    TurnoverYear = table.Column<DateTime>(nullable: false),
                    UserId = table.Column<string>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true),
                    ActualMainActivity1 = table.Column<string>(nullable: true),
                    ActualMainActivity2 = table.Column<string>(nullable: true),
                    ActualMainActivityDate = table.Column<string>(nullable: true),
                    Commercial = table.Column<bool>(nullable: true),
                    EntGroupId = table.Column<int>(nullable: true),
                    EntGroupIdDate = table.Column<DateTime>(nullable: true),
                    EntGroupRole = table.Column<string>(nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(nullable: true),
                    ForeignCapitalShare = table.Column<string>(nullable: true),
                    InstSectorCode = table.Column<string>(nullable: true),
                    MunCapitalShare = table.Column<string>(nullable: true),
                    PrivCapitalShare = table.Column<string>(nullable: true),
                    StateCapitalShare = table.Column<string>(nullable: true),
                    TotalCapital = table.Column<string>(nullable: true),
                    EntRegIdDate = table.Column<DateTime>(nullable: true),
                    EnterpriseGroupRegId = table.Column<int>(nullable: true),
                    EnterpriseUnitRegId = table.Column<int>(nullable: true),
                    Founders = table.Column<string>(nullable: true),
                    LegalForm = table.Column<string>(nullable: true),
                    Market = table.Column<bool>(nullable: true),
                    Owner = table.Column<string>(nullable: true),
                    LegalUnitId = table.Column<int>(nullable: true),
                    LegalUnitIdDate = table.Column<DateTime>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StatisticalUnits", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_StatisticalUnits_ParrentId",
                        column: x => x.ParrentId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Activities_RegMainActivityId",
                        column: x => x.RegMainActivityId,
                        principalTable: "Activities",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_EnterpriseGroups_EntGroupId",
                        column: x => x.EntGroupId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_EnterpriseGroups_EnterpriseGroupRegId",
                        column: x => x.EnterpriseGroupRegId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_StatisticalUnits_EnterpriseUnitRegId",
                        column: x => x.EnterpriseUnitRegId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_StatisticalUnits_LegalUnitId",
                        column: x => x.LegalUnitId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "DataSourceQueues",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    DataSourceFileName = table.Column<string>(nullable: false),
                    DataSourceId = table.Column<int>(nullable: false),
                    DataSourcePath = table.Column<string>(nullable: false),
                    Description = table.Column<string>(nullable: true),
                    EndImportDate = table.Column<DateTime>(nullable: false),
                    StartImportDate = table.Column<DateTime>(nullable: false),
                    Status = table.Column<int>(nullable: false),
                    UserId = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSourceQueues", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DataSourceQueues_DataSources_DataSourceId",
                        column: x => x.DataSourceId,
                        principalTable: "DataSources",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_DataSourceQueues_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "ActivityStatisticalUnits",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(nullable: false),
                    Activity_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityStatisticalUnits", x => new { x.Unit_Id, x.Activity_Id });
                    table.ForeignKey(
                        name: "FK_ActivityStatisticalUnits_Activities_Activity_Id",
                        column: x => x.Activity_Id,
                        principalTable: "Activities",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityStatisticalUnits_StatisticalUnits_Unit_Id",
                        column: x => x.Unit_Id,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "DataUploadingLogs",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    DataSourceQueueId = table.Column<int>(nullable: false),
                    EndImportDate = table.Column<DateTime>(nullable: false),
                    StartImportDate = table.Column<DateTime>(nullable: false),
                    StatUnitId = table.Column<string>(nullable: true),
                    StatUnitName = table.Column<string>(nullable: true),
                    StatUnitType = table.Column<int>(nullable: false),
                    Status = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataUploadingLogs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DataUploadingLogs_DataSourceQueues_DataSourceQueueId",
                        column: x => x.DataSourceQueueId,
                        principalTable: "DataSourceQueues",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AspNetRoleClaims_RoleId",
                table: "AspNetRoleClaims",
                column: "RoleId");

            migrationBuilder.CreateIndex(
                name: "IX_AspNetUserClaims_UserId",
                table: "AspNetUserClaims",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_AspNetUserLogins_UserId",
                table: "AspNetUserLogins",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_AspNetUserRoles_RoleId",
                table: "AspNetUserRoles",
                column: "RoleId");

            migrationBuilder.CreateIndex(
                name: "IX_Activities_Activity_Revx",
                table: "Activities",
                column: "Activity_Revx");

            migrationBuilder.CreateIndex(
                name: "IX_Activities_Updated_By",
                table: "Activities",
                column: "Updated_By");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityCategories_Code",
                table: "ActivityCategories",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ActivityStatisticalUnits_Activity_Id",
                table: "ActivityStatisticalUnits",
                column: "Activity_Id");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Geographical_codes_AddressDetails_GPS_coordinates",
                table: "Address",
                columns: new[] { "Geographical_codes", "AddressDetails", "GPS_coordinates" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DataSources_Name",
                table: "DataSources",
                column: "Name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DataSources_UserId",
                table: "DataSources",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_DataSourceQueues_DataSourceId",
                table: "DataSourceQueues",
                column: "DataSourceId");

            migrationBuilder.CreateIndex(
                name: "IX_DataSourceQueues_UserId",
                table: "DataSourceQueues",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_DataUploadingLogs_DataSourceQueueId",
                table: "DataUploadingLogs",
                column: "DataSourceQueueId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_ActualAddressId",
                table: "EnterpriseGroups",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_AddressId",
                table: "EnterpriseGroups",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_ParrentId",
                table: "EnterpriseGroups",
                column: "ParrentId");

            migrationBuilder.CreateIndex(
                name: "IX_Regions_Name",
                table: "Regions",
                column: "Name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "RoleNameIndex",
                table: "AspNetRoles",
                column: "NormalizedName",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Soates_Code",
                table: "Soates",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ActualAddressId",
                table: "StatisticalUnits",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_AddressId",
                table: "StatisticalUnits",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ParrentId",
                table: "StatisticalUnits",
                column: "ParrentId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_RegMainActivityId",
                table: "StatisticalUnits",
                column: "RegMainActivityId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_StatId",
                table: "StatisticalUnits",
                column: "StatId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EntGroupId",
                table: "StatisticalUnits",
                column: "EntGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EnterpriseGroupRegId",
                table: "StatisticalUnits",
                column: "EnterpriseGroupRegId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EnterpriseUnitRegId",
                table: "StatisticalUnits",
                column: "EnterpriseUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_LegalUnitId",
                table: "StatisticalUnits",
                column: "LegalUnitId");

            migrationBuilder.CreateIndex(
                name: "EmailIndex",
                table: "AspNetUsers",
                column: "NormalizedEmail");

            migrationBuilder.CreateIndex(
                name: "UserNameIndex",
                table: "AspNetUsers",
                column: "NormalizedUserName",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_AspNetUsers_RegionId",
                table: "AspNetUsers",
                column: "RegionId");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AspNetRoleClaims");

            migrationBuilder.DropTable(
                name: "AspNetUserClaims");

            migrationBuilder.DropTable(
                name: "AspNetUserLogins");

            migrationBuilder.DropTable(
                name: "AspNetUserRoles");

            migrationBuilder.DropTable(
                name: "AspNetUserTokens");

            migrationBuilder.DropTable(
                name: "ActivityStatisticalUnits");

            migrationBuilder.DropTable(
                name: "DataUploadingLogs");

            migrationBuilder.DropTable(
                name: "Soates");

            migrationBuilder.DropTable(
                name: "AspNetRoles");

            migrationBuilder.DropTable(
                name: "StatisticalUnits");

            migrationBuilder.DropTable(
                name: "DataSourceQueues");

            migrationBuilder.DropTable(
                name: "Activities");

            migrationBuilder.DropTable(
                name: "EnterpriseGroups");

            migrationBuilder.DropTable(
                name: "DataSources");

            migrationBuilder.DropTable(
                name: "ActivityCategories");

            migrationBuilder.DropTable(
                name: "Address");

            migrationBuilder.DropTable(
                name: "AspNetUsers");

            migrationBuilder.DropTable(
                name: "Regions");
        }
    }
}
