using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Metadata;

namespace nscreg.Data.Migrations
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
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Code = table.Column<string>(maxLength: 10, nullable: false),
                    DicParentId = table.Column<int>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: false),
                    ParentId = table.Column<int>(nullable: true),
                    Section = table.Column<string>(maxLength: 10, nullable: false),
                    VersionId = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategories", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Countries",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Code = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    IsoCode = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Countries", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DataSourceClassifications",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSourceClassifications", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DictionaryVersions",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    VersionId = table.Column<int>(nullable: false),
                    VersionName = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DictionaryVersions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ForeignParticipations",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ForeignParticipations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "LegalForms",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Code = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    Name = table.Column<string>(nullable: false),
                    ParentId = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LegalForms", x => x.Id);
                    table.ForeignKey(
                        name: "FK_LegalForms_LegalForms_ParentId",
                        column: x => x.ParentId,
                        principalTable: "LegalForms",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "PostalIndices",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PostalIndices", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Regions",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    AdminstrativeCenter = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    Name = table.Column<string>(nullable: false),
                    ParentId = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Regions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ReorgTypes",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReorgTypes", x => x.Id);
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
                name: "SectorCodes",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Code = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    Name = table.Column<string>(nullable: false),
                    ParentId = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SectorCodes", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SectorCodes_SectorCodes_ParentId",
                        column: x => x.ParentId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "UnitsSize",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UnitsSize", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "UnitStatuses",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UnitStatuses", x => x.Id);
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
                    SecurityStamp = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    SuspensionDate = table.Column<DateTime>(nullable: true),
                    TwoFactorEnabled = table.Column<bool>(nullable: false),
                    UserName = table.Column<string>(maxLength: 256, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUsers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "V_StatUnitSearch",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    AddressPart1 = table.Column<string>(nullable: true),
                    AddressPart2 = table.Column<string>(nullable: true),
                    AddressPart3 = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    ExternalId = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    LegalFormId = table.Column<int>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    ParentId = table.Column<int>(nullable: true),
                    RegionId = table.Column<int>(nullable: true),
                    SectorCodeId = table.Column<int>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    UnitType = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_V_StatUnitSearch", x => x.RegId);
                });

            migrationBuilder.CreateTable(
                name: "Persons",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Address = table.Column<string>(nullable: true),
                    BirthDate = table.Column<DateTime>(nullable: true),
                    CountryId = table.Column<int>(nullable: false),
                    GivenName = table.Column<string>(nullable: true),
                    IdDate = table.Column<DateTime>(nullable: false),
                    PersonalId = table.Column<string>(nullable: true),
                    PhoneNumber = table.Column<string>(nullable: true),
                    PhoneNumber1 = table.Column<string>(nullable: true),
                    Role = table.Column<int>(nullable: false),
                    Sex = table.Column<byte>(nullable: false),
                    Surname = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Persons", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Persons_Countries_CountryId",
                        column: x => x.CountryId,
                        principalTable: "Countries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Address",
                columns: table => new
                {
                    Address_id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Address_part1 = table.Column<string>(nullable: true),
                    Address_part2 = table.Column<string>(nullable: true),
                    Address_part3 = table.Column<string>(nullable: true),
                    GPS_coordinates = table.Column<string>(nullable: true),
                    Region_id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Address", x => x.Address_id);
                    table.ForeignKey(
                        name: "FK_Address_Regions_Region_id",
                        column: x => x.Region_id,
                        principalTable: "Regions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoleClaims",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
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
                name: "ActivityCategoryRoles",
                columns: table => new
                {
                    Role_Id = table.Column<string>(nullable: false),
                    Activity_Category_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategoryRoles", x => new { x.Role_Id, x.Activity_Category_Id });
                    table.ForeignKey(
                        name: "FK_ActivityCategoryRoles_ActivityCategories_Activity_Category_Id",
                        column: x => x.Activity_Category_Id,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityCategoryRoles_AspNetRoles_Role_Id",
                        column: x => x.Role_Id,
                        principalTable: "AspNetRoles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserClaims",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
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
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    ActivityCategoryId = table.Column<int>(nullable: false),
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
                        name: "FK_Activities_ActivityCategories_ActivityCategoryId",
                        column: x => x.ActivityCategoryId,
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
                name: "AnalysisQueues",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Comment = table.Column<string>(nullable: true),
                    ServerEndPeriod = table.Column<DateTime>(nullable: true),
                    ServerStartPeriod = table.Column<DateTime>(nullable: true),
                    UserEndPeriod = table.Column<DateTime>(nullable: false),
                    UserId = table.Column<string>(nullable: false),
                    UserStartPeriod = table.Column<DateTime>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AnalysisQueues", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AnalysisQueues_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "DataSources",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    AllowedOperations = table.Column<int>(nullable: false),
                    AttributesToCheck = table.Column<string>(nullable: true),
                    CsvDelimiter = table.Column<string>(nullable: true),
                    CsvSkipCount = table.Column<int>(nullable: false),
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
                name: "SampleFrames",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Fields = table.Column<string>(nullable: false),
                    Name = table.Column<string>(nullable: false),
                    Predicate = table.Column<string>(nullable: false),
                    UserId = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SampleFrames", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SampleFrames_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "UserRegions",
                columns: table => new
                {
                    User_Id = table.Column<string>(nullable: false),
                    Region_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserRegions", x => new { x.User_Id, x.Region_Id });
                    table.ForeignKey(
                        name: "FK_UserRegions_Regions_Region_Id",
                        column: x => x.Region_Id,
                        principalTable: "Regions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_UserRegions_AspNetUsers_User_Id",
                        column: x => x.User_Id,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AnalysisLogs",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    AnalysisQueueId = table.Column<int>(nullable: false),
                    AnalyzedUnitId = table.Column<int>(nullable: false),
                    AnalyzedUnitType = table.Column<int>(nullable: false),
                    ErrorValues = table.Column<string>(nullable: true),
                    SummaryMessages = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AnalysisLogs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AnalysisLogs_AnalysisQueues_AnalysisQueueId",
                        column: x => x.AnalysisQueueId,
                        principalTable: "AnalysisQueues",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "DataSourceQueues",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    DataSourceFileName = table.Column<string>(nullable: false),
                    DataSourceId = table.Column<int>(nullable: false),
                    DataSourcePath = table.Column<string>(nullable: false),
                    Description = table.Column<string>(nullable: true),
                    EndImportDate = table.Column<DateTime>(nullable: true),
                    StartImportDate = table.Column<DateTime>(nullable: true),
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
                name: "DataUploadingLogs",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    DataSourceQueueId = table.Column<int>(nullable: false),
                    EndImportDate = table.Column<DateTime>(nullable: true),
                    Errors = table.Column<string>(nullable: true),
                    Note = table.Column<string>(nullable: true),
                    SerializedUnit = table.Column<string>(nullable: true),
                    StartImportDate = table.Column<DateTime>(nullable: true),
                    StatUnitName = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    Summary = table.Column<string>(nullable: true),
                    TargetStatId = table.Column<string>(nullable: true)
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
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseGroups",
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
                    ExternalIdType = table.Column<int>(nullable: true),
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
                    ParrentRegId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: true),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegMainActivityId = table.Column<int>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    Size = table.Column<int>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    StatisticalUnitRegId = table.Column<int>(nullable: true),
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
                        name: "FK_EnterpriseGroups_DataSourceClassifications_DataSourceClassificationId",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_EnterpriseGroups_ParrentRegId",
                        column: x => x.ParrentRegId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "StatisticalUnits",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    ActualAddressId = table.Column<int>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    Classified = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
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
                    ForeignParticipation = table.Column<string>(nullable: true),
                    ForeignParticipationCountryId = table.Column<int>(nullable: true),
                    ForeignParticipationId = table.Column<int>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    InstSectorCodeId = table.Column<int>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    LegalFormId = table.Column<int>(nullable: true),
                    LiqDate = table.Column<string>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(maxLength: 400, nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    NumOfPeopleEmp = table.Column<int>(nullable: true),
                    ParentId = table.Column<int>(nullable: true),
                    ParentOrgLink = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: false),
                    RefNo = table.Column<int>(nullable: true),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    Size = table.Column<int>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(maxLength: 15, nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    StatisticalUnitRegId = table.Column<int>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    StatusDate = table.Column<DateTime>(nullable: true),
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
                    Founders = table.Column<string>(nullable: true),
                    HistoryLocalUnitIds = table.Column<string>(nullable: true),
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
                        name: "FK_StatisticalUnits_DataSourceClassifications_DataSourceClassificationId",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Countries_ForeignParticipationCountryId",
                        column: x => x.ForeignParticipationCountryId,
                        principalTable: "Countries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_SectorCodes_InstSectorCodeId",
                        column: x => x.InstSectorCodeId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_LegalForms_LegalFormId",
                        column: x => x.LegalFormId,
                        principalTable: "LegalForms",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_StatisticalUnits_ParentId",
                        column: x => x.ParentId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_StatisticalUnits_StatisticalUnitRegId",
                        column: x => x.StatisticalUnitRegId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_EnterpriseGroups_EntGroupId",
                        column: x => x.EntGroupId,
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
                name: "CountryStatisticalUnits",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(nullable: false),
                    Country_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CountryStatisticalUnits", x => new { x.Unit_Id, x.Country_Id });
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnits_Countries_Country_Id",
                        column: x => x.Country_Id,
                        principalTable: "Countries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnits_StatisticalUnits_Unit_Id",
                        column: x => x.Unit_Id,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PersonStatisticalUnits",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(nullable: false),
                    Person_Id = table.Column<int>(nullable: false),
                    PersonType = table.Column<int>(nullable: false),
                    GroupUnit_Id = table.Column<int>(nullable: true),
                    StatUnit_Id = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonStatisticalUnits", x => new { x.Unit_Id, x.Person_Id, x.PersonType });
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_EnterpriseGroups_GroupUnit_Id",
                        column: x => x.GroupUnit_Id,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_Persons_Person_Id",
                        column: x => x.Person_Id,
                        principalTable: "Persons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_StatisticalUnits_StatUnit_Id",
                        column: x => x.StatUnit_Id,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_StatisticalUnits_Unit_Id",
                        column: x => x.Unit_Id,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
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
                name: "IX_Activities_ActivityCategoryId",
                table: "Activities",
                column: "ActivityCategoryId");

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
                name: "IX_ActivityCategoryRoles_Activity_Category_Id",
                table: "ActivityCategoryRoles",
                column: "Activity_Category_Id");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityStatisticalUnits_Activity_Id",
                table: "ActivityStatisticalUnits",
                column: "Activity_Id");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Region_id",
                table: "Address",
                column: "Region_id");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_GPS_coordinates",
                table: "Address",
                columns: new[] { "Address_part1", "Address_part2", "Address_part3", "Region_id", "GPS_coordinates" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_AnalysisLogs_AnalysisQueueId",
                table: "AnalysisLogs",
                column: "AnalysisQueueId");

            migrationBuilder.CreateIndex(
                name: "IX_AnalysisQueues_UserId",
                table: "AnalysisQueues",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnits_Country_Id",
                table: "CountryStatisticalUnits",
                column: "Country_Id");

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
                name: "IX_DictionaryVersions_VersionId_VersionName",
                table: "DictionaryVersions",
                columns: new[] { "VersionId", "VersionName" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_ActualAddressId",
                table: "EnterpriseGroups",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_AddressId",
                table: "EnterpriseGroups",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_DataSourceClassificationId",
                table: "EnterpriseGroups",
                column: "DataSourceClassificationId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_Name",
                table: "EnterpriseGroups",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_ParrentRegId",
                table: "EnterpriseGroups",
                column: "ParrentRegId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_StatisticalUnitRegId",
                table: "EnterpriseGroups",
                column: "StatisticalUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalForms_ParentId",
                table: "LegalForms",
                column: "ParentId");

            migrationBuilder.CreateIndex(
                name: "IX_Persons_CountryId",
                table: "Persons",
                column: "CountryId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_GroupUnit_Id",
                table: "PersonStatisticalUnits",
                column: "GroupUnit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_Person_Id",
                table: "PersonStatisticalUnits",
                column: "Person_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_StatUnit_Id",
                table: "PersonStatisticalUnits",
                column: "StatUnit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_Regions_Code",
                table: "Regions",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "RoleNameIndex",
                table: "AspNetRoles",
                column: "NormalizedName",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_SampleFrames_UserId",
                table: "SampleFrames",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_SectorCodes_Code",
                table: "SectorCodes",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_SectorCodes_ParentId",
                table: "SectorCodes",
                column: "ParentId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ActualAddressId",
                table: "StatisticalUnits",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_AddressId",
                table: "StatisticalUnits",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_DataSourceClassificationId",
                table: "StatisticalUnits",
                column: "DataSourceClassificationId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ForeignParticipationCountryId",
                table: "StatisticalUnits",
                column: "ForeignParticipationCountryId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_InstSectorCodeId",
                table: "StatisticalUnits",
                column: "InstSectorCodeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_LegalFormId",
                table: "StatisticalUnits",
                column: "LegalFormId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_Name",
                table: "StatisticalUnits",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ParentId",
                table: "StatisticalUnits",
                column: "ParentId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_StatId",
                table: "StatisticalUnits",
                column: "StatId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_StatisticalUnitRegId",
                table: "StatisticalUnits",
                column: "StatisticalUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EntGroupId",
                table: "StatisticalUnits",
                column: "EntGroupId");

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
                name: "IX_UserRegions_Region_Id",
                table: "UserRegions",
                column: "Region_Id");

            migrationBuilder.AddForeignKey(
                name: "FK_ActivityStatisticalUnits_StatisticalUnits_Unit_Id",
                table: "ActivityStatisticalUnits",
                column: "Unit_Id",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_StatisticalUnits_StatisticalUnitRegId",
                table: "EnterpriseGroups",
                column: "StatisticalUnitRegId",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_StatisticalUnits_StatisticalUnitRegId",
                table: "EnterpriseGroups");

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
                name: "ActivityCategoryRoles");

            migrationBuilder.DropTable(
                name: "ActivityStatisticalUnits");

            migrationBuilder.DropTable(
                name: "AnalysisLogs");

            migrationBuilder.DropTable(
                name: "CountryStatisticalUnits");

            migrationBuilder.DropTable(
                name: "DataUploadingLogs");

            migrationBuilder.DropTable(
                name: "DictionaryVersions");

            migrationBuilder.DropTable(
                name: "ForeignParticipations");

            migrationBuilder.DropTable(
                name: "PersonStatisticalUnits");

            migrationBuilder.DropTable(
                name: "PostalIndices");

            migrationBuilder.DropTable(
                name: "ReorgTypes");

            migrationBuilder.DropTable(
                name: "SampleFrames");

            migrationBuilder.DropTable(
                name: "UnitsSize");

            migrationBuilder.DropTable(
                name: "UnitStatuses");

            migrationBuilder.DropTable(
                name: "UserRegions");

            migrationBuilder.DropTable(
                name: "V_StatUnitSearch");

            migrationBuilder.DropTable(
                name: "AspNetRoles");

            migrationBuilder.DropTable(
                name: "Activities");

            migrationBuilder.DropTable(
                name: "AnalysisQueues");

            migrationBuilder.DropTable(
                name: "DataSourceQueues");

            migrationBuilder.DropTable(
                name: "Persons");

            migrationBuilder.DropTable(
                name: "ActivityCategories");

            migrationBuilder.DropTable(
                name: "DataSources");

            migrationBuilder.DropTable(
                name: "AspNetUsers");

            migrationBuilder.DropTable(
                name: "StatisticalUnits");

            migrationBuilder.DropTable(
                name: "Countries");

            migrationBuilder.DropTable(
                name: "SectorCodes");

            migrationBuilder.DropTable(
                name: "LegalForms");

            migrationBuilder.DropTable(
                name: "EnterpriseGroups");

            migrationBuilder.DropTable(
                name: "Address");

            migrationBuilder.DropTable(
                name: "DataSourceClassifications");

            migrationBuilder.DropTable(
                name: "Regions");
        }
    }
}
