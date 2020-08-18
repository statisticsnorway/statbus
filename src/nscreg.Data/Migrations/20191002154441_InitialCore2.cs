using System;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class InitialCore2 : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ActivityCategories",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(maxLength: 10, nullable: false),
                    Section = table.Column<string>(maxLength: 10, nullable: false),
                    ParentId = table.Column<int>(nullable: true),
                    DicParentId = table.Column<int>(nullable: true),
                    VersionId = table.Column<int>(nullable: false),
                    ActivityCategoryLevel = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategories", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoles",
                columns: table => new
                {
                    Id = table.Column<string>(nullable: false),
                    Name = table.Column<string>(maxLength: 256, nullable: true),
                    NormalizedName = table.Column<string>(maxLength: 256, nullable: true),
                    ConcurrencyStamp = table.Column<string>(nullable: true),
                    Description = table.Column<string>(nullable: true),
                    AccessToSystemFunctions = table.Column<string>(nullable: true),
                    StandardDataAccess = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    SqlWalletUser = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetRoles", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUsers",
                columns: table => new
                {
                    Id = table.Column<string>(nullable: false),
                    UserName = table.Column<string>(maxLength: 256, nullable: true),
                    NormalizedUserName = table.Column<string>(maxLength: 256, nullable: true),
                    Email = table.Column<string>(maxLength: 256, nullable: true),
                    NormalizedEmail = table.Column<string>(maxLength: 256, nullable: true),
                    EmailConfirmed = table.Column<bool>(nullable: false),
                    PasswordHash = table.Column<string>(nullable: true),
                    SecurityStamp = table.Column<string>(nullable: true),
                    ConcurrencyStamp = table.Column<string>(nullable: true),
                    PhoneNumber = table.Column<string>(nullable: true),
                    PhoneNumberConfirmed = table.Column<bool>(nullable: false),
                    TwoFactorEnabled = table.Column<bool>(nullable: false),
                    LockoutEnd = table.Column<DateTimeOffset>(nullable: true),
                    LockoutEnabled = table.Column<bool>(nullable: false),
                    AccessFailedCount = table.Column<int>(nullable: false),
                    Name = table.Column<string>(nullable: true),
                    Description = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    DataAccess = table.Column<string>(nullable: true),
                    CreationDate = table.Column<DateTime>(nullable: false),
                    SuspensionDate = table.Column<DateTime>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUsers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Countries",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true),
                    IsoCode = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Countries", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "CustomAnalysisChecks",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(maxLength: 64, nullable: true),
                    Query = table.Column<string>(maxLength: 2048, nullable: true),
                    TargetUnitTypes = table.Column<string>(maxLength: 16, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CustomAnalysisChecks", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DataSourceClassifications",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true)
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
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true)
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
                    Name = table.Column<string>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true),
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
                name: "PersonTypes",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonTypes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "PostalIndices",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true)
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
                    Name = table.Column<string>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true),
                    AdminstrativeCenter = table.Column<string>(nullable: true),
                    ParentId = table.Column<int>(nullable: true),
                    FullPath = table.Column<string>(nullable: true),
                    FullPathLanguage1 = table.Column<string>(nullable: true),
                    FullPathLanguage2 = table.Column<string>(nullable: true),
                    RegionLevel = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Regions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Regions_Regions_ParentId",
                        column: x => x.ParentId,
                        principalTable: "Regions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "RegistrationReasons",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RegistrationReasons", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ReorgTypes",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReorgTypes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ReportTree",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Title = table.Column<string>(nullable: true),
                    Type = table.Column<string>(nullable: true),
                    ReportId = table.Column<int>(nullable: true),
                    ParentNodeId = table.Column<int>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    ResourceGroup = table.Column<string>(nullable: true),
                    ReportUrl = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReportTree", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "SectorCodes",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true),
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
                name: "Statuses",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Statuses", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "UnitsSize",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UnitsSize", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "V_StatUnitSearch",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    StatId = table.Column<string>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    ExternalId = table.Column<string>(nullable: true),
                    RegionId = table.Column<int>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    SectorCodeId = table.Column<int>(nullable: true),
                    LegalFormId = table.Column<int>(nullable: true),
                    DataSourceClassificationId = table.Column<int>(nullable: true),
                    ChangeReason = table.Column<int>(nullable: false),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    UnitType = table.Column<int>(nullable: false),
                    IsDeleted = table.Column<bool>(nullable: false),
                    LiqReason = table.Column<string>(nullable: true),
                    LiqDate = table.Column<DateTime>(nullable: true),
                    AddressPart1 = table.Column<string>(nullable: true),
                    AddressPart2 = table.Column<string>(nullable: true),
                    AddressPart3 = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_V_StatUnitSearch", x => x.RegId);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoleClaims",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    RoleId = table.Column<string>(nullable: false),
                    ClaimType = table.Column<string>(nullable: true),
                    ClaimValue = table.Column<string>(nullable: true)
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
                name: "Activities",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Id_Date = table.Column<DateTime>(nullable: false),
                    ActivityCategoryId = table.Column<int>(nullable: false),
                    Activity_Year = table.Column<int>(nullable: false),
                    Activity_Type = table.Column<int>(nullable: false),
                    Employees = table.Column<int>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
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
                name: "ActivityCategoryUsers",
                columns: table => new
                {
                    User_Id = table.Column<string>(nullable: false),
                    ActivityCategory_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategoryUsers", x => new { x.User_Id, x.ActivityCategory_Id });
                    table.ForeignKey(
                        name: "FK_ActivityCategoryUsers_ActivityCategories_ActivityCategory_Id",
                        column: x => x.ActivityCategory_Id,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityCategoryUsers_AspNetUsers_User_Id",
                        column: x => x.User_Id,
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
                    UserStartPeriod = table.Column<DateTime>(nullable: false),
                    UserEndPeriod = table.Column<DateTime>(nullable: false),
                    UserId = table.Column<string>(nullable: false),
                    Comment = table.Column<string>(nullable: true),
                    ServerStartPeriod = table.Column<DateTime>(nullable: true),
                    ServerEndPeriod = table.Column<DateTime>(nullable: true)
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
                name: "AspNetUserClaims",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    UserId = table.Column<string>(nullable: false),
                    ClaimType = table.Column<string>(nullable: true),
                    ClaimValue = table.Column<string>(nullable: true)
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
                    table.ForeignKey(
                        name: "FK_AspNetUserTokens_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "DataSourceUploads",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: false),
                    Description = table.Column<string>(nullable: true),
                    UserId = table.Column<string>(nullable: true),
                    Priority = table.Column<int>(nullable: false),
                    AllowedOperations = table.Column<int>(nullable: false),
                    AttributesToCheck = table.Column<string>(nullable: true),
                    StatUnitType = table.Column<int>(nullable: false),
                    Restrictions = table.Column<string>(nullable: true),
                    VariablesMapping = table.Column<string>(nullable: true),
                    CsvDelimiter = table.Column<string>(nullable: true),
                    CsvSkipCount = table.Column<int>(nullable: false),
                    DataSourceUploadType = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSourceUploads", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DataSourceUploads_AspNetUsers_UserId",
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
                    Name = table.Column<string>(nullable: false),
                    Description = table.Column<string>(nullable: true),
                    Predicate = table.Column<string>(nullable: false),
                    Fields = table.Column<string>(nullable: false),
                    UserId = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    FilePath = table.Column<string>(nullable: true),
                    GeneratedDateTime = table.Column<DateTime>(nullable: true),
                    CreationDate = table.Column<DateTime>(nullable: false),
                    EditingDate = table.Column<DateTime>(nullable: true)
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
                name: "Persons",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IdDate = table.Column<DateTime>(nullable: false),
                    GivenName = table.Column<string>(maxLength: 150, nullable: true),
                    PersonalId = table.Column<string>(nullable: true),
                    Surname = table.Column<string>(maxLength: 150, nullable: true),
                    MiddleName = table.Column<string>(maxLength: 150, nullable: true),
                    BirthDate = table.Column<DateTime>(nullable: true),
                    Sex = table.Column<byte>(nullable: false),
                    CountryId = table.Column<int>(nullable: false),
                    PhoneNumber = table.Column<string>(nullable: true),
                    PhoneNumber1 = table.Column<string>(nullable: true),
                    Address = table.Column<string>(nullable: true)
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
                    Address_part1 = table.Column<string>(nullable: true, maxLength: 200),
                    Address_part2 = table.Column<string>(nullable: true, maxLength: 200),
                    Address_part3 = table.Column<string>(nullable: true, maxLength: 200),
                    Region_id = table.Column<int>(nullable: false),
                    Latitude = table.Column<double>(nullable: true),
                    Longitude = table.Column<double>(nullable: true)
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
                    IssuedAt = table.Column<DateTime>(nullable: false),
                    ResolvedAt = table.Column<DateTime>(nullable: true),
                    SummaryMessages = table.Column<string>(nullable: true),
                    ErrorValues = table.Column<string>(nullable: true)
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
                    StartImportDate = table.Column<DateTime>(nullable: true),
                    EndImportDate = table.Column<DateTime>(nullable: true),
                    DataSourcePath = table.Column<string>(nullable: false),
                    DataSourceFileName = table.Column<string>(nullable: false),
                    Description = table.Column<string>(nullable: true),
                    Status = table.Column<int>(nullable: false),
                    Note = table.Column<string>(nullable: true),
                    DataSourceId = table.Column<int>(nullable: false),
                    UserId = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSourceQueues", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DataSourceQueues_DataSourceUploads_DataSourceId",
                        column: x => x.DataSourceId,
                        principalTable: "DataSourceUploads",
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
                name: "EnterpriseGroups",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    Name = table.Column<string>(maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReasonId = table.Column<int>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: true),
                    ExternalId = table.Column<string>(nullable: true),
                    ExternalIdType = table.Column<string>(nullable: true),
                    ExternalIdDate = table.Column<DateTime>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    AddressId = table.Column<int>(nullable: true),
                    ActualAddressId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: true),
                    EntGroupType = table.Column<string>(nullable: true),
                    NumOfPeopleEmp = table.Column<int>(nullable: true),
                    TelephoneNo = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    WebAddress = table.Column<string>(nullable: true),
                    LiqDateStart = table.Column<DateTime>(nullable: true),
                    LiqDateEnd = table.Column<DateTime>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    LiqReason = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    EmployeesYear = table.Column<int>(nullable: true),
                    EmployeesDate = table.Column<DateTime>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    TurnoverYear = table.Column<int>(nullable: true),
                    TurnoverDate = table.Column<DateTime>(nullable: true),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    Notes = table.Column<string>(nullable: true),
                    UserId = table.Column<string>(nullable: false),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(nullable: true),
                    HistoryEnterpriseUnitIds = table.Column<string>(nullable: true),
                    RegMainActivityId = table.Column<int>(nullable: true),
                    InstSectorCodeId = table.Column<int>(nullable: true),
                    LegalFormId = table.Column<int>(nullable: true),
                    SizeId = table.Column<int>(nullable: true),
                    DataSourceClassificationId = table.Column<int>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    UnitStatusId = table.Column<int>(nullable: true)
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
                        name: "FK_EnterpriseGroups_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_UnitsSize_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitsSize",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Statuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "Statuses",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseGroupsHistory",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    Name = table.Column<string>(maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReasonId = table.Column<int>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: true),
                    ExternalId = table.Column<string>(nullable: true),
                    ExternalIdType = table.Column<string>(nullable: true),
                    ExternalIdDate = table.Column<DateTime>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    ParentId = table.Column<int>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    ActualAddressId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: true),
                    EntGroupType = table.Column<string>(nullable: true),
                    NumOfPeopleEmp = table.Column<int>(nullable: true),
                    TelephoneNo = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    WebAddress = table.Column<string>(nullable: true),
                    LiqDateStart = table.Column<DateTime>(nullable: true),
                    LiqDateEnd = table.Column<DateTime>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    LiqReason = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    EmployeesYear = table.Column<int>(nullable: true),
                    EmployeesDate = table.Column<DateTime>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    TurnoverYear = table.Column<int>(nullable: true),
                    TurnoverDate = table.Column<DateTime>(nullable: true),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    Notes = table.Column<string>(nullable: true),
                    UserId = table.Column<string>(nullable: false),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(nullable: true),
                    HistoryEnterpriseUnitIds = table.Column<string>(nullable: true),
                    RegMainActivityId = table.Column<int>(nullable: true),
                    InstSectorCodeId = table.Column<int>(nullable: true),
                    LegalFormId = table.Column<int>(nullable: true),
                    SizeId = table.Column<int>(nullable: true),
                    DataSourceClassificationId = table.Column<int>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    UnitStatusId = table.Column<int>(nullable: true)
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
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_UnitsSize_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitsSize",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "DataUploadingLogs",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    StartImportDate = table.Column<DateTime>(nullable: true),
                    EndImportDate = table.Column<DateTime>(nullable: true),
                    TargetStatId = table.Column<string>(nullable: true),
                    StatUnitName = table.Column<string>(nullable: true),
                    SerializedUnit = table.Column<string>(nullable: true),
                    SerializedRawUnit = table.Column<string>(nullable: true),
                    DataSourceQueueId = table.Column<int>(nullable: false),
                    Status = table.Column<int>(nullable: false),
                    Note = table.Column<string>(nullable: true),
                    Errors = table.Column<string>(nullable: true),
                    Summary = table.Column<string>(nullable: true)
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
                name: "StatisticalUnits",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(maxLength: 15, nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    Name = table.Column<string>(maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    ParentOrgLink = table.Column<int>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: true),
                    RegistrationReasonId = table.Column<int>(nullable: true),
                    ExternalId = table.Column<string>(nullable: true),
                    ExternalIdDate = table.Column<DateTime>(nullable: true),
                    ExternalIdType = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    WebAddress = table.Column<string>(nullable: true),
                    TelephoneNo = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    ActualAddressId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    ForeignParticipationCountryId = table.Column<int>(nullable: true),
                    NumOfPeopleEmp = table.Column<int>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    EmployeesYear = table.Column<int>(nullable: true),
                    EmployeesDate = table.Column<DateTime>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    TurnoverDate = table.Column<DateTime>(nullable: true),
                    TurnoverYear = table.Column<int>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    Classified = table.Column<bool>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: true),
                    RefNo = table.Column<int>(nullable: true),
                    InstSectorCodeId = table.Column<int>(nullable: true),
                    LegalFormId = table.Column<int>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    LiqDate = table.Column<DateTime>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<DateTime>(nullable: true),
                    SuspensionEnd = table.Column<DateTime>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<int>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    UserId = table.Column<string>(nullable: false),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(nullable: true),
                    SizeId = table.Column<int>(nullable: true),
                    ForeignParticipationId = table.Column<int>(nullable: true),
                    DataSourceClassificationId = table.Column<int>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    UnitStatusId = table.Column<int>(nullable: true),
                    Discriminator = table.Column<string>(nullable: false),
                    EntGroupId = table.Column<int>(nullable: true),
                    EntGroupIdDate = table.Column<DateTime>(nullable: true),
                    EntGroupRole = table.Column<string>(nullable: true),
                    Commercial = table.Column<bool>(nullable: true),
                    TotalCapital = table.Column<string>(nullable: true),
                    MunCapitalShare = table.Column<string>(nullable: true),
                    StateCapitalShare = table.Column<string>(nullable: true),
                    PrivCapitalShare = table.Column<string>(nullable: true),
                    ForeignCapitalShare = table.Column<string>(nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(nullable: true),
                    HistoryLegalUnitIds = table.Column<string>(nullable: true),
                    EnterpriseUnitRegId = table.Column<int>(nullable: true),
                    EntRegIdDate = table.Column<DateTime>(nullable: true),
                    Market = table.Column<bool>(nullable: true),
                    HistoryLocalUnitIds = table.Column<string>(nullable: true),
                    LegalUnitId = table.Column<int>(nullable: true),
                    LegalUnitIdDate = table.Column<DateTime>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StatisticalUnits", x => x.RegId);
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
                        name: "FK_StatisticalUnits_DataSourceClassifications_Id",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Countries_Id",
                        column: x => x.ForeignParticipationCountryId,
                        principalTable: "Countries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_ForeignParticipations_ForeignParticipationId",
                        column: x => x.ForeignParticipationId,
                        principalTable: "ForeignParticipations",
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
                        name: "FK_StatisticalUnits_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_UnitsSize_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitsSize",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Statuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "Statuses",
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
                    StatUnit_Id = table.Column<int>(nullable: true),
                    GroupUnit_Id = table.Column<int>(nullable: true),
                    PersonTypeId = table.Column<int>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonStatisticalUnits", x => new { x.Unit_Id, x.Person_Id });
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
                        name: "FK_PersonStatisticalUnits_PersonTypes_PersonTypeId",
                        column: x => x.PersonTypeId,
                        principalTable: "PersonTypes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_StatisticalUnits_Id",
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

            migrationBuilder.CreateTable(
                name: "StatisticalUnitHistory",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    StatId = table.Column<string>(maxLength: 15, nullable: true),
                    StatIdDate = table.Column<DateTime>(nullable: true),
                    Name = table.Column<string>(maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    ParentOrgLink = table.Column<int>(nullable: true),
                    TaxRegId = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: true),
                    RegistrationReasonId = table.Column<int>(nullable: true),
                    ExternalId = table.Column<string>(nullable: true),
                    ExternalIdDate = table.Column<DateTime>(nullable: true),
                    ExternalIdType = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    AddressId = table.Column<int>(nullable: true),
                    WebAddress = table.Column<string>(nullable: true),
                    TelephoneNo = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    ActualAddressId = table.Column<int>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    ForeignParticipationCountryId = table.Column<int>(nullable: true),
                    NumOfPeopleEmp = table.Column<int>(nullable: true),
                    Employees = table.Column<int>(nullable: true),
                    EmployeesYear = table.Column<int>(nullable: true),
                    EmployeesDate = table.Column<DateTime>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    TurnoverDate = table.Column<DateTime>(nullable: true),
                    TurnoverYear = table.Column<int>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    Classified = table.Column<bool>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: true),
                    RefNo = table.Column<int>(nullable: true),
                    InstSectorCodeId = table.Column<int>(nullable: true),
                    LegalFormId = table.Column<int>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    LiqDate = table.Column<DateTime>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<DateTime>(nullable: true),
                    SuspensionEnd = table.Column<DateTime>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: true),
                    ReorgReferences = table.Column<int>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    ParentId = table.Column<int>(nullable: true),
                    StartPeriod = table.Column<DateTime>(nullable: false),
                    EndPeriod = table.Column<DateTime>(nullable: false),
                    UserId = table.Column<string>(nullable: false),
                    ChangeReason = table.Column<int>(nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(nullable: true),
                    SizeId = table.Column<int>(nullable: true),
                    ForeignParticipationId = table.Column<int>(nullable: true),
                    DataSourceClassificationId = table.Column<int>(nullable: true),
                    ReorgTypeId = table.Column<int>(nullable: true),
                    UnitStatusId = table.Column<int>(nullable: true),
                    Discriminator = table.Column<string>(nullable: false),
                    EntGroupId = table.Column<int>(nullable: true),
                    EntGroupIdDate = table.Column<DateTime>(nullable: true),
                    EntGroupRole = table.Column<string>(nullable: true),
                    Commercial = table.Column<bool>(nullable: true),
                    TotalCapital = table.Column<string>(nullable: true),
                    MunCapitalShare = table.Column<string>(nullable: true),
                    StateCapitalShare = table.Column<string>(nullable: true),
                    PrivCapitalShare = table.Column<string>(nullable: true),
                    ForeignCapitalShare = table.Column<string>(nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(nullable: true),
                    HistoryLegalUnitIds = table.Column<string>(nullable: true),
                    EnterpriseUnitRegId = table.Column<int>(nullable: true),
                    EntRegIdDate = table.Column<DateTime>(nullable: true),
                    Market = table.Column<bool>(nullable: true),
                    HistoryLocalUnitIds = table.Column<string>(nullable: true),
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
                        name: "FK_StatisticalUnitHistory_DataSourceClassifications_Id",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Countries_Id",
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
                        name: "FK_StatisticalUnitHistory_RegistrationReasons_Id",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_UnitsSize_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitsSize",
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
                    StatUnit_Id = table.Column<int>(nullable: true),
                    GroupUnit_Id = table.Column<int>(nullable: true),
                    PersonTypeId = table.Column<int>(nullable: true)
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
                name: "IX_ActivityCategoryUsers_ActivityCategory_Id",
                table: "ActivityCategoryUsers",
                column: "ActivityCategory_Id");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityStatisticalUnitHistory_Activity_Id",
                table: "ActivityStatisticalUnitHistory",
                column: "Activity_Id");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityStatisticalUnits_Activity_Id",
                table: "ActivityStatisticalUnits",
                column: "Activity_Id");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Region_id",
                table: "Address",
                column: "Region_id");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_Latitude_Longitude",
                table: "Address",
                columns: new[] { "Address_part1", "Address_part2", "Address_part3", "Region_id", "Latitude", "Longitude" });

            migrationBuilder.CreateIndex(
                name: "IX_AnalysisLogs_AnalysisQueueId",
                table: "AnalysisLogs",
                column: "AnalysisQueueId");

            migrationBuilder.CreateIndex(
                name: "IX_AnalysisQueues_UserId",
                table: "AnalysisQueues",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_AspNetRoleClaims_RoleId",
                table: "AspNetRoleClaims",
                column: "RoleId");

            migrationBuilder.CreateIndex(
                name: "RoleNameIndex",
                table: "AspNetRoles",
                column: "NormalizedName",
                unique: true,
                filter: "[NormalizedName] IS NOT NULL");

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
                name: "EmailIndex",
                table: "AspNetUsers",
                column: "NormalizedEmail");

            migrationBuilder.CreateIndex(
                name: "UserNameIndex",
                table: "AspNetUsers",
                column: "NormalizedUserName",
                unique: true,
                filter: "[NormalizedUserName] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnitHistory_Country_Id",
                table: "CountryStatisticalUnitHistory",
                column: "Country_Id");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnits_Country_Id",
                table: "CountryStatisticalUnits",
                column: "Country_Id");

            migrationBuilder.CreateIndex(
                name: "IX_DataSourceQueues_DataSourceId",
                table: "DataSourceQueues",
                column: "DataSourceId");

            migrationBuilder.CreateIndex(
                name: "IX_DataSourceQueues_UserId",
                table: "DataSourceQueues",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_DataSourceUploads_Name",
                table: "DataSourceUploads",
                column: "Name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DataSourceUploads_UserId",
                table: "DataSourceUploads",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_DataUploadingLogs_DataSourceQueueId",
                table: "DataUploadingLogs",
                column: "DataSourceQueueId");

            migrationBuilder.CreateIndex(
                name: "IX_DictionaryVersions_VersionId_VersionName",
                table: "DictionaryVersions",
                columns: new[] { "VersionId", "VersionName" },
                unique: true,
                filter: "[VersionName] IS NOT NULL");

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
                name: "IX_EnterpriseGroups_PostalAddressId",
                table: "EnterpriseGroups",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_RegistrationReasonId",
                table: "EnterpriseGroups",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_ReorgTypeId",
                table: "EnterpriseGroups",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_SizeId",
                table: "EnterpriseGroups",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_StartPeriod",
                table: "EnterpriseGroups",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_UnitStatusId",
                table: "EnterpriseGroups",
                column: "UnitStatusId");

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
                name: "IX_EnterpriseGroupsHistory_SizeId",
                table: "EnterpriseGroupsHistory",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_StartPeriod",
                table: "EnterpriseGroupsHistory",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_LegalForms_ParentId",
                table: "LegalForms",
                column: "ParentId");

            migrationBuilder.CreateIndex(
                name: "IX_Persons_CountryId",
                table: "Persons",
                column: "CountryId");

            migrationBuilder.CreateIndex(
                name: "IX_Persons_GivenName_Surname",
                table: "Persons",
                columns: new[] { "GivenName", "Surname" });

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
                unique: true,
                filter: "[PersonTypeId] IS NOT NULL");

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
                name: "IX_PersonStatisticalUnits_PersonTypeId_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits",
                columns: new[] { "PersonTypeId", "Unit_Id", "Person_Id" },
                unique: true,
                filter: "[PersonTypeId] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Regions_Code",
                table: "Regions",
                column: "Code",
                unique: true,
                filter: "[Code] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Regions_ParentId",
                table: "Regions",
                column: "ParentId");

            migrationBuilder.CreateIndex(
                name: "IX_RegistrationReasons_Code",
                table: "RegistrationReasons",
                column: "Code",
                unique: true,
                filter: "[Code] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_SampleFrames_UserId",
                table: "SampleFrames",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_SectorCodes_Code",
                table: "SectorCodes",
                column: "Code",
                unique: true,
                filter: "[Code] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_SectorCodes_ParentId",
                table: "SectorCodes",
                column: "ParentId");

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
                name: "IX_StatisticalUnitHistory_CountryId",
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
                name: "IX_StatisticalUnitHistory_SizeId",
                table: "StatisticalUnitHistory",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_StartPeriod",
                table: "StatisticalUnitHistory",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_StatId",
                table: "StatisticalUnitHistory",
                column: "StatId");

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
                name: "IX_StatisticalUnits_CountryId",
                table: "StatisticalUnits",
                column: "ForeignParticipationCountryId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ForeignParticipationId",
                table: "StatisticalUnits",
                column: "ForeignParticipationId");

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
                name: "IX_StatisticalUnits_PostalAddressId",
                table: "StatisticalUnits",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_RegistrationReasonId",
                table: "StatisticalUnits",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ReorgTypeId",
                table: "StatisticalUnits",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_SizeId",
                table: "StatisticalUnits",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_StartPeriod",
                table: "StatisticalUnits",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_StatId",
                table: "StatisticalUnits",
                column: "StatId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_UnitStatusId",
                table: "StatisticalUnits",
                column: "UnitStatusId");

            migrationBuilder.CreateIndex(
                name: "IX_UserRegions_Region_Id",
                table: "UserRegions",
                column: "Region_Id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ActivityCategoryUsers");

            migrationBuilder.DropTable(
                name: "ActivityStatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "ActivityStatisticalUnits");

            migrationBuilder.DropTable(
                name: "AnalysisLogs");

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
                name: "CountryStatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "CountryStatisticalUnits");

            migrationBuilder.DropTable(
                name: "CustomAnalysisChecks");

            migrationBuilder.DropTable(
                name: "DataUploadingLogs");

            migrationBuilder.DropTable(
                name: "DictionaryVersions");

            migrationBuilder.DropTable(
                name: "EnterpriseGroupsHistory");

            migrationBuilder.DropTable(
                name: "PersonStatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "PersonStatisticalUnits");

            migrationBuilder.DropTable(
                name: "PostalIndices");

            migrationBuilder.DropTable(
                name: "ReportTree");

            migrationBuilder.DropTable(
                name: "SampleFrames");

            migrationBuilder.DropTable(
                name: "UserRegions");

            migrationBuilder.DropTable(
                name: "V_StatUnitSearch");

            migrationBuilder.DropTable(
                name: "Activities");

            migrationBuilder.DropTable(
                name: "AnalysisQueues");

            migrationBuilder.DropTable(
                name: "AspNetRoles");

            migrationBuilder.DropTable(
                name: "DataSourceQueues");

            migrationBuilder.DropTable(
                name: "StatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "Persons");

            migrationBuilder.DropTable(
                name: "PersonTypes");

            migrationBuilder.DropTable(
                name: "ActivityCategories");

            migrationBuilder.DropTable(
                name: "DataSourceUploads");

            migrationBuilder.DropTable(
                name: "StatisticalUnits");

            migrationBuilder.DropTable(
                name: "AspNetUsers");

            migrationBuilder.DropTable(
                name: "EnterpriseGroups");

            migrationBuilder.DropTable(
                name: "Countries");

            migrationBuilder.DropTable(
                name: "ForeignParticipations");

            migrationBuilder.DropTable(
                name: "SectorCodes");

            migrationBuilder.DropTable(
                name: "LegalForms");

            migrationBuilder.DropTable(
                name: "Address");

            migrationBuilder.DropTable(
                name: "DataSourceClassifications");

            migrationBuilder.DropTable(
                name: "RegistrationReasons");

            migrationBuilder.DropTable(
                name: "ReorgTypes");

            migrationBuilder.DropTable(
                name: "UnitsSize");

            migrationBuilder.DropTable(
                name: "Statuses");

            migrationBuilder.DropTable(
                name: "Regions");
        }
    }
}
