using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace nscreg.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ActivityCategories",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Section = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    ParentId = table.Column<int>(type: "integer", nullable: true),
                    DicParentId = table.Column<int>(type: "integer", nullable: true),
                    VersionId = table.Column<int>(type: "integer", nullable: false),
                    ActivityCategoryLevel = table.Column<int>(type: "integer", nullable: true),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategories", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ActivityCategories_ActivityCategories_ParentId",
                        column: x => x.ParentId,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoles",
                columns: table => new
                {
                    Id = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    AccessToSystemFunctions = table.Column<string>(type: "text", nullable: true),
                    StandardDataAccess = table.Column<string>(type: "text", nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    SqlWalletUser = table.Column<string>(type: "text", nullable: true),
                    Name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    NormalizedName = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    ConcurrencyStamp = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetRoles", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUsers",
                columns: table => new
                {
                    Id = table.Column<string>(type: "text", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: true),
                    Description = table.Column<string>(type: "text", nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    DataAccess = table.Column<string>(type: "text", nullable: true),
                    CreationDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    SuspensionDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    UserName = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    NormalizedUserName = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    Email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    NormalizedEmail = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    EmailConfirmed = table.Column<bool>(type: "boolean", nullable: false),
                    PasswordHash = table.Column<string>(type: "text", nullable: true),
                    SecurityStamp = table.Column<string>(type: "text", nullable: true),
                    ConcurrencyStamp = table.Column<string>(type: "text", nullable: true),
                    PhoneNumber = table.Column<string>(type: "text", nullable: true),
                    PhoneNumberConfirmed = table.Column<bool>(type: "boolean", nullable: false),
                    TwoFactorEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    LockoutEnd = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LockoutEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    AccessFailedCount = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AspNetUsers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Countries",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    IsoCode = table.Column<string>(type: "text", nullable: true),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Countries", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "CustomAnalysisChecks",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    Query = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    TargetUnitTypes = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CustomAnalysisChecks", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DataSourceClassifications",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSourceClassifications", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DictionaryVersions",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    VersionId = table.Column<int>(type: "integer", nullable: false),
                    VersionName = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DictionaryVersions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseGroupRoles",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroupRoles", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseGroupTypes",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroupTypes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ForeignParticipations",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ForeignParticipations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "LegalForms",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LegalForms", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "PersonTypes",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonTypes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "PostalIndices",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PostalIndices", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Regions",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    AdminstrativeCenter = table.Column<string>(type: "text", nullable: true),
                    ParentId = table.Column<int>(type: "integer", nullable: true),
                    FullPath = table.Column<string>(type: "text", nullable: true),
                    FullPathLanguage1 = table.Column<string>(type: "text", nullable: true),
                    FullPathLanguage2 = table.Column<string>(type: "text", nullable: true),
                    RegionLevel = table.Column<int>(type: "integer", nullable: true),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Regions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Regions_Regions_ParentId",
                        column: x => x.ParentId,
                        principalTable: "Regions",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "RegistrationReasons",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RegistrationReasons", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ReorgTypes",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReorgTypes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ReportTree",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Title = table.Column<string>(type: "text", nullable: true),
                    Type = table.Column<string>(type: "text", nullable: true),
                    ReportId = table.Column<int>(type: "integer", nullable: true),
                    ParentNodeId = table.Column<int>(type: "integer", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    ResourceGroup = table.Column<string>(type: "text", nullable: true),
                    ReportUrl = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReportTree", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "SectorCodes",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ParentId = table.Column<int>(type: "integer", nullable: true),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SectorCodes", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SectorCodes_SectorCodes_ParentId",
                        column: x => x.ParentId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "UnitSizes",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Code = table.Column<int>(type: "integer", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UnitSizes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "UnitStatuses",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    NameLanguage1 = table.Column<string>(type: "text", nullable: true),
                    NameLanguage2 = table.Column<string>(type: "text", nullable: true),
                    Code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UnitStatuses", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoleClaims",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    RoleId = table.Column<string>(type: "text", nullable: false),
                    ClaimType = table.Column<string>(type: "text", nullable: true),
                    ClaimValue = table.Column<string>(type: "text", nullable: true)
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
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Id_Date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ActivityCategoryId = table.Column<int>(type: "integer", nullable: false),
                    Activity_Year = table.Column<int>(type: "integer", nullable: true),
                    Activity_Type = table.Column<int>(type: "integer", nullable: false),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    Updated_By = table.Column<string>(type: "text", nullable: false),
                    Updated_Date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
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
                name: "ActivitiesHistory",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Id_Date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ActivityCategoryId = table.Column<int>(type: "integer", nullable: false),
                    Activity_Year = table.Column<int>(type: "integer", nullable: true),
                    Activity_Type = table.Column<int>(type: "integer", nullable: false),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    Updated_By = table.Column<string>(type: "text", nullable: false),
                    Updated_Date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ParentId = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivitiesHistory", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ActivitiesHistory_ActivityCategories_ActivityCategoryId",
                        column: x => x.ActivityCategoryId,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivitiesHistory_AspNetUsers_Updated_By",
                        column: x => x.Updated_By,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ActivityCategoryUsers",
                columns: table => new
                {
                    User_Id = table.Column<string>(type: "text", nullable: false),
                    ActivityCategory_Id = table.Column<int>(type: "integer", nullable: false)
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
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    UserStartPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UserEndPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UserId = table.Column<string>(type: "text", nullable: false),
                    Comment = table.Column<string>(type: "text", nullable: true),
                    ServerStartPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ServerEndPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
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
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    UserId = table.Column<string>(type: "text", nullable: false),
                    ClaimType = table.Column<string>(type: "text", nullable: true),
                    ClaimValue = table.Column<string>(type: "text", nullable: true)
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
                    LoginProvider = table.Column<string>(type: "text", nullable: false),
                    ProviderKey = table.Column<string>(type: "text", nullable: false),
                    ProviderDisplayName = table.Column<string>(type: "text", nullable: true),
                    UserId = table.Column<string>(type: "text", nullable: false)
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
                    UserId = table.Column<string>(type: "text", nullable: false),
                    RoleId = table.Column<string>(type: "text", nullable: false)
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
                    UserId = table.Column<string>(type: "text", nullable: false),
                    LoginProvider = table.Column<string>(type: "text", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Value = table.Column<string>(type: "text", nullable: true)
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
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    UserId = table.Column<string>(type: "text", nullable: true),
                    Priority = table.Column<int>(type: "integer", nullable: false),
                    AllowedOperations = table.Column<int>(type: "integer", nullable: false),
                    AttributesToCheck = table.Column<string>(type: "text", nullable: true),
                    OriginalCsvAttributes = table.Column<string>(type: "text", nullable: true),
                    StatUnitType = table.Column<int>(type: "integer", nullable: false),
                    Restrictions = table.Column<string>(type: "text", nullable: true),
                    VariablesMapping = table.Column<string>(type: "text", nullable: true),
                    CsvDelimiter = table.Column<string>(type: "text", nullable: true),
                    CsvSkipCount = table.Column<int>(type: "integer", nullable: false),
                    DataSourceUploadType = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSourceUploads", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DataSourceUploads_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "SampleFrames",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    Predicate = table.Column<string>(type: "text", nullable: false),
                    Fields = table.Column<string>(type: "text", nullable: false),
                    UserId = table.Column<string>(type: "text", nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    FilePath = table.Column<string>(type: "text", nullable: true),
                    GeneratedDateTime = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreationDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    EditingDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SampleFrames", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SampleFrames_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "Persons",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    IdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    GivenName = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    PersonalId = table.Column<string>(type: "text", nullable: true),
                    Surname = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    MiddleName = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    BirthDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Sex = table.Column<byte>(type: "smallint", nullable: true),
                    CountryId = table.Column<int>(type: "integer", nullable: true),
                    PhoneNumber = table.Column<string>(type: "text", nullable: true),
                    PhoneNumber1 = table.Column<string>(type: "text", nullable: true),
                    Address = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Persons", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Persons_Countries_CountryId",
                        column: x => x.CountryId,
                        principalTable: "Countries",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "Address",
                columns: table => new
                {
                    Address_id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Address_part1 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Address_part2 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Address_part3 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Region_id = table.Column<int>(type: "integer", nullable: false),
                    Latitude = table.Column<double>(type: "double precision", nullable: true),
                    Longitude = table.Column<double>(type: "double precision", nullable: true)
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
                    User_Id = table.Column<string>(type: "text", nullable: false),
                    Region_Id = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserRegions", x => new { x.User_Id, x.Region_Id });
                    table.ForeignKey(
                        name: "FK_UserRegions_AspNetUsers_User_Id",
                        column: x => x.User_Id,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_UserRegions_Regions_Region_Id",
                        column: x => x.Region_Id,
                        principalTable: "Regions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AnalysisLogs",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    AnalysisQueueId = table.Column<int>(type: "integer", nullable: false),
                    AnalyzedUnitId = table.Column<int>(type: "integer", nullable: false),
                    AnalyzedUnitType = table.Column<int>(type: "integer", nullable: false),
                    IssuedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ResolvedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SummaryMessages = table.Column<string>(type: "text", nullable: true),
                    ErrorValues = table.Column<string>(type: "text", nullable: true)
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
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    StartImportDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    EndImportDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    DataSourcePath = table.Column<string>(type: "text", nullable: false),
                    DataSourceFileName = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Note = table.Column<string>(type: "text", nullable: true),
                    DataSourceId = table.Column<int>(type: "integer", nullable: false),
                    UserId = table.Column<string>(type: "text", nullable: true),
                    SkipLinesCount = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DataSourceQueues", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DataSourceQueues_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_DataSourceQueues_DataSourceUploads_DataSourceId",
                        column: x => x.DataSourceId,
                        principalTable: "DataSourceUploads",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseGroups",
                columns: table => new
                {
                    RegId = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    RegIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    StatId = table.Column<string>(type: "text", nullable: true),
                    StatIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(type: "text", nullable: true),
                    RegistrationDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    RegistrationReasonId = table.Column<int>(type: "integer", nullable: true),
                    TaxRegId = table.Column<string>(type: "text", nullable: true),
                    TaxRegDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExternalId = table.Column<string>(type: "text", nullable: true),
                    ExternalIdType = table.Column<string>(type: "text", nullable: true),
                    ExternalIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    DataSource = table.Column<string>(type: "text", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    AddressId = table.Column<int>(type: "integer", nullable: true),
                    ActualAddressId = table.Column<int>(type: "integer", nullable: true),
                    PostalAddressId = table.Column<int>(type: "integer", nullable: true),
                    EntGroupTypeId = table.Column<int>(type: "integer", nullable: true),
                    NumOfPeopleEmp = table.Column<int>(type: "integer", nullable: true),
                    TelephoneNo = table.Column<string>(type: "text", nullable: true),
                    EmailAddress = table.Column<string>(type: "text", nullable: true),
                    WebAddress = table.Column<string>(type: "text", nullable: true),
                    LiqDateStart = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LiqDateEnd = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReorgTypeCode = table.Column<string>(type: "text", nullable: true),
                    ReorgReferences = table.Column<string>(type: "text", nullable: true),
                    ContactPerson = table.Column<string>(type: "text", nullable: true),
                    StartPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    EndPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LiqReason = table.Column<string>(type: "text", nullable: true),
                    SuspensionStart = table.Column<string>(type: "text", nullable: true),
                    SuspensionEnd = table.Column<string>(type: "text", nullable: true),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    EmployeesYear = table.Column<int>(type: "integer", nullable: true),
                    EmployeesDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    TurnoverYear = table.Column<int>(type: "integer", nullable: true),
                    TurnoverDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    StatusDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    UserId = table.Column<string>(type: "text", nullable: false),
                    ChangeReason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(type: "text", nullable: true),
                    HistoryEnterpriseUnitIds = table.Column<string>(type: "text", nullable: true),
                    SizeId = table.Column<int>(type: "integer", nullable: true),
                    DataSourceClassificationId = table.Column<int>(type: "integer", nullable: true),
                    ReorgTypeId = table.Column<int>(type: "integer", nullable: true),
                    ReorgDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    UnitStatusId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroups", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_DataSourceClassifications_DataSourceClassi~",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_EnterpriseGroupTypes_EntGroupTypeId",
                        column: x => x.EntGroupTypeId,
                        principalTable: "EnterpriseGroupTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_UnitSizes_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitSizes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_UnitStatuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "UnitStatuses",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseGroupsHistory",
                columns: table => new
                {
                    RegId = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    RegIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    StatId = table.Column<string>(type: "text", nullable: true),
                    StatIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(type: "text", nullable: true),
                    RegistrationDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    RegistrationReasonId = table.Column<int>(type: "integer", nullable: true),
                    TaxRegId = table.Column<string>(type: "text", nullable: true),
                    TaxRegDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExternalId = table.Column<string>(type: "text", nullable: true),
                    ExternalIdType = table.Column<string>(type: "text", nullable: true),
                    ExternalIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    DataSource = table.Column<string>(type: "text", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    ParentId = table.Column<int>(type: "integer", nullable: true),
                    AddressId = table.Column<int>(type: "integer", nullable: true),
                    ActualAddressId = table.Column<int>(type: "integer", nullable: true),
                    PostalAddressId = table.Column<int>(type: "integer", nullable: true),
                    EntGroupTypeId = table.Column<int>(type: "integer", nullable: true),
                    NumOfPeopleEmp = table.Column<int>(type: "integer", nullable: true),
                    TelephoneNo = table.Column<string>(type: "text", nullable: true),
                    EmailAddress = table.Column<string>(type: "text", nullable: true),
                    WebAddress = table.Column<string>(type: "text", nullable: true),
                    LiqDateStart = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LiqDateEnd = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReorgTypeCode = table.Column<string>(type: "text", nullable: true),
                    ReorgDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReorgReferences = table.Column<string>(type: "text", nullable: true),
                    ContactPerson = table.Column<string>(type: "text", nullable: true),
                    StartPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    EndPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LiqReason = table.Column<string>(type: "text", nullable: true),
                    SuspensionStart = table.Column<string>(type: "text", nullable: true),
                    SuspensionEnd = table.Column<string>(type: "text", nullable: true),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    EmployeesYear = table.Column<int>(type: "integer", nullable: true),
                    EmployeesDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    TurnoverYear = table.Column<int>(type: "integer", nullable: true),
                    TurnoverDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    StatusDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    UserId = table.Column<string>(type: "text", nullable: false),
                    ChangeReason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(type: "text", nullable: true),
                    HistoryEnterpriseUnitIds = table.Column<string>(type: "text", nullable: true),
                    SizeId = table.Column<int>(type: "integer", nullable: true),
                    DataSourceClassificationId = table.Column<int>(type: "integer", nullable: true),
                    ReorgTypeId = table.Column<int>(type: "integer", nullable: true),
                    UnitStatusId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroupsHistory", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_DataSourceClassifications_DataSourc~",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_EnterpriseGroupTypes_EntGroupTypeId",
                        column: x => x.EntGroupTypeId,
                        principalTable: "EnterpriseGroupTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_RegistrationReasons_RegistrationRea~",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_UnitSizes_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitSizes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroupsHistory_UnitStatuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "UnitStatuses",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "DataUploadingLogs",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    StartImportDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    EndImportDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    TargetStatId = table.Column<string>(type: "text", nullable: true),
                    StatUnitName = table.Column<string>(type: "text", nullable: true),
                    SerializedUnit = table.Column<string>(type: "text", nullable: true),
                    SerializedRawUnit = table.Column<string>(type: "text", nullable: true),
                    DataSourceQueueId = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Note = table.Column<string>(type: "text", nullable: true),
                    Errors = table.Column<string>(type: "text", nullable: true),
                    Summary = table.Column<string>(type: "text", nullable: true)
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
                    RegId = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    RegIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    StatId = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    StatIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ParentOrgLink = table.Column<int>(type: "integer", nullable: true),
                    TaxRegId = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    TaxRegDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RegistrationReasonId = table.Column<int>(type: "integer", nullable: true),
                    RegistrationDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExternalId = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ExternalIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExternalIdType = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    DataSource = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AddressId = table.Column<int>(type: "integer", nullable: true),
                    WebAddress = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    TelephoneNo = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    EmailAddress = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ActualAddressId = table.Column<int>(type: "integer", nullable: true),
                    PostalAddressId = table.Column<int>(type: "integer", nullable: true),
                    FreeEconZone = table.Column<bool>(type: "boolean", nullable: false),
                    NumOfPeopleEmp = table.Column<int>(type: "integer", nullable: true),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    EmployeesYear = table.Column<int>(type: "integer", nullable: true),
                    EmployeesDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    TurnoverDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    TurnoverYear = table.Column<int>(type: "integer", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    Classified = table.Column<bool>(type: "boolean", nullable: true),
                    StatusDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RefNo = table.Column<string>(type: "character varying(25)", maxLength: 25, nullable: true),
                    InstSectorCodeId = table.Column<int>(type: "integer", nullable: true),
                    LegalFormId = table.Column<int>(type: "integer", nullable: true),
                    LiqDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LiqReason = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    SuspensionStart = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SuspensionEnd = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReorgTypeCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ReorgDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReorgReferences = table.Column<int>(type: "integer", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    StartPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    EndPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UserId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    ChangeReason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    SizeId = table.Column<int>(type: "integer", nullable: true),
                    ForeignParticipationId = table.Column<int>(type: "integer", nullable: true),
                    DataSourceClassificationId = table.Column<int>(type: "integer", nullable: true),
                    ReorgTypeId = table.Column<int>(type: "integer", nullable: true),
                    UnitStatusId = table.Column<int>(type: "integer", nullable: true),
                    Discriminator = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    EntGroupId = table.Column<int>(type: "integer", nullable: true),
                    EntGroupIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Commercial = table.Column<bool>(type: "boolean", nullable: true),
                    TotalCapital = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    MunCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    StateCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    PrivCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    HistoryLegalUnitIds = table.Column<string>(type: "text", nullable: true),
                    EntGroupRoleId = table.Column<int>(type: "integer", nullable: true),
                    EnterpriseUnitRegId = table.Column<int>(type: "integer", nullable: true),
                    EntRegIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Market = table.Column<bool>(type: "boolean", nullable: true),
                    HistoryLocalUnitIds = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    LegalUnitId = table.Column<int>(type: "integer", nullable: true),
                    LegalUnitIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StatisticalUnits", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_DataSourceClassifications_DataSourceClassi~",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_EnterpriseGroupRoles_EntGroupRoleId",
                        column: x => x.EntGroupRoleId,
                        principalTable: "EnterpriseGroupRoles",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_EnterpriseGroups_EntGroupId",
                        column: x => x.EntGroupId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_ForeignParticipations_ForeignParticipation~",
                        column: x => x.ForeignParticipationId,
                        principalTable: "ForeignParticipations",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_LegalForms_LegalFormId",
                        column: x => x.LegalFormId,
                        principalTable: "LegalForms",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_SectorCodes_InstSectorCodeId",
                        column: x => x.InstSectorCodeId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_StatisticalUnits_EnterpriseUnitRegId",
                        column: x => x.EnterpriseUnitRegId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_StatisticalUnits_LegalUnitId",
                        column: x => x.LegalUnitId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_UnitSizes_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitSizes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnits_UnitStatuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "UnitStatuses",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "ActivityStatisticalUnits",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(type: "integer", nullable: false),
                    Activity_Id = table.Column<int>(type: "integer", nullable: false)
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
                    Unit_Id = table.Column<int>(type: "integer", nullable: false),
                    Country_Id = table.Column<int>(type: "integer", nullable: false)
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
                    Unit_Id = table.Column<int>(type: "integer", nullable: false),
                    Person_Id = table.Column<int>(type: "integer", nullable: false),
                    GroupUnit_Id = table.Column<int>(type: "integer", nullable: true),
                    PersonTypeId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonStatisticalUnits", x => new { x.Unit_Id, x.Person_Id });
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_EnterpriseGroups_GroupUnit_Id",
                        column: x => x.GroupUnit_Id,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_PersonTypes_PersonTypeId",
                        column: x => x.PersonTypeId,
                        principalTable: "PersonTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_Persons_Person_Id",
                        column: x => x.Person_Id,
                        principalTable: "Persons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
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
                    RegId = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    RegIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    StatId = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    StatIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(type: "text", nullable: true),
                    ParentOrgLink = table.Column<int>(type: "integer", nullable: true),
                    TaxRegId = table.Column<string>(type: "text", nullable: true),
                    TaxRegDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RegistrationReasonId = table.Column<int>(type: "integer", nullable: true),
                    ExternalId = table.Column<string>(type: "text", nullable: true),
                    ExternalIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExternalIdType = table.Column<string>(type: "text", nullable: true),
                    DataSource = table.Column<string>(type: "text", nullable: true),
                    AddressId = table.Column<int>(type: "integer", nullable: true),
                    WebAddress = table.Column<string>(type: "text", nullable: true),
                    TelephoneNo = table.Column<string>(type: "text", nullable: true),
                    EmailAddress = table.Column<string>(type: "text", nullable: true),
                    ActualAddressId = table.Column<int>(type: "integer", nullable: true),
                    PostalAddressId = table.Column<int>(type: "integer", nullable: true),
                    FreeEconZone = table.Column<bool>(type: "boolean", nullable: false),
                    NumOfPeopleEmp = table.Column<int>(type: "integer", nullable: true),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    EmployeesYear = table.Column<int>(type: "integer", nullable: true),
                    EmployeesDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    TurnoverDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    TurnoverYear = table.Column<int>(type: "integer", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    Classified = table.Column<bool>(type: "boolean", nullable: true),
                    StatusDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RefNo = table.Column<string>(type: "character varying(25)", maxLength: 25, nullable: true),
                    InstSectorCodeId = table.Column<int>(type: "integer", nullable: true),
                    LegalFormId = table.Column<int>(type: "integer", nullable: true),
                    RegistrationDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LiqDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LiqReason = table.Column<string>(type: "text", nullable: true),
                    SuspensionStart = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SuspensionEnd = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReorgTypeCode = table.Column<string>(type: "text", nullable: true),
                    ReorgDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReorgReferences = table.Column<int>(type: "integer", nullable: true),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    ParentId = table.Column<int>(type: "integer", nullable: true),
                    StartPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    EndPeriod = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UserId = table.Column<string>(type: "text", nullable: false),
                    ChangeReason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(type: "text", nullable: true),
                    SizeId = table.Column<int>(type: "integer", nullable: true),
                    ForeignParticipationId = table.Column<int>(type: "integer", nullable: true),
                    DataSourceClassificationId = table.Column<int>(type: "integer", nullable: true),
                    ReorgTypeId = table.Column<int>(type: "integer", nullable: true),
                    UnitStatusId = table.Column<int>(type: "integer", nullable: true),
                    Discriminator = table.Column<string>(type: "text", nullable: false),
                    EntGroupId = table.Column<int>(type: "integer", nullable: true),
                    EntGroupIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    EntGroupRole = table.Column<string>(type: "text", nullable: true),
                    Commercial = table.Column<bool>(type: "boolean", nullable: true),
                    TotalCapital = table.Column<string>(type: "text", nullable: true),
                    MunCapitalShare = table.Column<string>(type: "text", nullable: true),
                    StateCapitalShare = table.Column<string>(type: "text", nullable: true),
                    PrivCapitalShare = table.Column<string>(type: "text", nullable: true),
                    ForeignCapitalShare = table.Column<string>(type: "text", nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(type: "text", nullable: true),
                    HistoryLegalUnitIds = table.Column<string>(type: "text", nullable: true),
                    EnterpriseUnitRegId = table.Column<int>(type: "integer", nullable: true),
                    EntRegIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Market = table.Column<bool>(type: "boolean", nullable: true),
                    HistoryLocalUnitIds = table.Column<string>(type: "text", nullable: true),
                    LegalUnitId = table.Column<int>(type: "integer", nullable: true),
                    LegalUnitIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StatisticalUnitHistory", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Address_id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_DataSourceClassifications_DataSource~",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_LegalForms_LegalFormId",
                        column: x => x.LegalFormId,
                        principalTable: "LegalForms",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_RegistrationReasons_RegistrationReas~",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_SectorCodes_InstSectorCodeId",
                        column: x => x.InstSectorCodeId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_StatisticalUnits_ParentId",
                        column: x => x.ParentId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_StatisticalUnitHistory_UnitSizes_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitSizes",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "ActivityStatisticalUnitHistory",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(type: "integer", nullable: false),
                    Activity_Id = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityStatisticalUnitHistory", x => new { x.Unit_Id, x.Activity_Id });
                    table.ForeignKey(
                        name: "FK_ActivityStatisticalUnitHistory_ActivitiesHistory_Activity_Id",
                        column: x => x.Activity_Id,
                        principalTable: "ActivitiesHistory",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityStatisticalUnitHistory_StatisticalUnitHistory_Unit_~",
                        column: x => x.Unit_Id,
                        principalTable: "StatisticalUnitHistory",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "CountryStatisticalUnitHistory",
                columns: table => new
                {
                    Unit_Id = table.Column<int>(type: "integer", nullable: false),
                    Country_Id = table.Column<int>(type: "integer", nullable: false)
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
                    Unit_Id = table.Column<int>(type: "integer", nullable: false),
                    Person_Id = table.Column<int>(type: "integer", nullable: false),
                    GroupUnit_Id = table.Column<int>(type: "integer", nullable: true),
                    PersonTypeId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonStatisticalUnitHistory", x => new { x.Unit_Id, x.Person_Id });
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnitHistory_PersonTypes_PersonTypeId",
                        column: x => x.PersonTypeId,
                        principalTable: "PersonTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnitHistory_Persons_Person_Id",
                        column: x => x.Person_Id,
                        principalTable: "Persons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
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
                name: "IX_ActivitiesHistory_ActivityCategoryId",
                table: "ActivitiesHistory",
                column: "ActivityCategoryId");

            migrationBuilder.CreateIndex(
                name: "IX_ActivitiesHistory_Updated_By",
                table: "ActivitiesHistory",
                column: "Updated_By");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityCategories_Code",
                table: "ActivityCategories",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ActivityCategories_ParentId",
                table: "ActivityCategories",
                column: "ParentId");

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
                name: "IX_ActivityStatisticalUnits_Unit_Id",
                table: "ActivityStatisticalUnits",
                column: "Unit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id~",
                table: "Address",
                columns: new[] { "Address_part1", "Address_part2", "Address_part3", "Region_id", "Latitude", "Longitude" });

            migrationBuilder.CreateIndex(
                name: "IX_Address_Region_id",
                table: "Address",
                column: "Region_id");

            migrationBuilder.CreateIndex(
                name: "IX_AnalysisLogs_AnalysisQueueId_AnalyzedUnitId",
                table: "AnalysisLogs",
                columns: new[] { "AnalysisQueueId", "AnalyzedUnitId" });

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
                unique: true);

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
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Countries_Code",
                table: "Countries",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnitHistory_Country_Id",
                table: "CountryStatisticalUnitHistory",
                column: "Country_Id");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnits_Country_Id",
                table: "CountryStatisticalUnits",
                column: "Country_Id");

            migrationBuilder.CreateIndex(
                name: "IX_DataSourceClassifications_Code",
                table: "DataSourceClassifications",
                column: "Code",
                unique: true);

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
                name: "IX_EnterpriseGroupRoles_Code",
                table: "EnterpriseGroupRoles",
                column: "Code",
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
                name: "IX_EnterpriseGroups_EntGroupTypeId",
                table: "EnterpriseGroups",
                column: "EntGroupTypeId");

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
                name: "IX_EnterpriseGroupsHistory_EntGroupTypeId",
                table: "EnterpriseGroupsHistory",
                column: "EntGroupTypeId");

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
                name: "IX_EnterpriseGroupsHistory_ReorgTypeId",
                table: "EnterpriseGroupsHistory",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_SizeId",
                table: "EnterpriseGroupsHistory",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_StartPeriod",
                table: "EnterpriseGroupsHistory",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_UnitStatusId",
                table: "EnterpriseGroupsHistory",
                column: "UnitStatusId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupTypes_Code",
                table: "EnterpriseGroupTypes",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ForeignParticipations_Code",
                table: "ForeignParticipations",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_LegalForms_Code",
                table: "LegalForms",
                column: "Code",
                unique: true);

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
                name: "IX_PersonStatisticalUnitHistory_PersonTypeId_Unit_Id_Person_Id",
                table: "PersonStatisticalUnitHistory",
                columns: new[] { "PersonTypeId", "Unit_Id", "Person_Id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_GroupUnit_Id",
                table: "PersonStatisticalUnits",
                column: "GroupUnit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_Person_Id",
                table: "PersonStatisticalUnits",
                column: "Person_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_PersonTypeId_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits",
                columns: new[] { "PersonTypeId", "Unit_Id", "Person_Id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_Unit_Id",
                table: "PersonStatisticalUnits",
                column: "Unit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_Regions_Code",
                table: "Regions",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Regions_ParentId",
                table: "Regions",
                column: "ParentId");

            migrationBuilder.CreateIndex(
                name: "IX_RegistrationReasons_Code",
                table: "RegistrationReasons",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ReorgTypes_Code",
                table: "ReorgTypes",
                column: "Code",
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
                name: "IX_StatisticalUnitHistory_EnterpriseUnitRegId",
                table: "StatisticalUnitHistory",
                column: "EnterpriseUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_EntGroupId",
                table: "StatisticalUnitHistory",
                column: "EntGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_InstSectorCodeId",
                table: "StatisticalUnitHistory",
                column: "InstSectorCodeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_LegalFormId",
                table: "StatisticalUnitHistory",
                column: "LegalFormId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_LegalUnitId",
                table: "StatisticalUnitHistory",
                column: "LegalUnitId");

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
                name: "IX_StatisticalUnitHistory_StatId_EndPeriod",
                table: "StatisticalUnitHistory",
                columns: new[] { "StatId", "EndPeriod" });

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
                name: "IX_StatisticalUnits_Discriminator",
                table: "StatisticalUnits",
                column: "Discriminator");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EnterpriseUnitRegId",
                table: "StatisticalUnits",
                column: "EnterpriseUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EntGroupId",
                table: "StatisticalUnits",
                column: "EntGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EntGroupRoleId",
                table: "StatisticalUnits",
                column: "EntGroupRoleId");

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
                name: "IX_StatisticalUnits_LegalUnitId",
                table: "StatisticalUnits",
                column: "LegalUnitId");

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
                name: "IX_StatisticalUnits_ShortName_RegId_Discriminator_StatId_TaxRe~",
                table: "StatisticalUnits",
                columns: new[] { "ShortName", "RegId", "Discriminator", "StatId", "TaxRegId" });

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
                name: "IX_UnitSizes_Code",
                table: "UnitSizes",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_UnitStatuses_Code",
                table: "UnitStatuses",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_UserRegions_Region_Id",
                table: "UserRegions",
                column: "Region_Id");
        }

        /// <inheritdoc />
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
                name: "ActivitiesHistory");

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
                name: "PersonTypes");

            migrationBuilder.DropTable(
                name: "Persons");

            migrationBuilder.DropTable(
                name: "ActivityCategories");

            migrationBuilder.DropTable(
                name: "DataSourceUploads");

            migrationBuilder.DropTable(
                name: "StatisticalUnits");

            migrationBuilder.DropTable(
                name: "Countries");

            migrationBuilder.DropTable(
                name: "AspNetUsers");

            migrationBuilder.DropTable(
                name: "EnterpriseGroupRoles");

            migrationBuilder.DropTable(
                name: "EnterpriseGroups");

            migrationBuilder.DropTable(
                name: "ForeignParticipations");

            migrationBuilder.DropTable(
                name: "LegalForms");

            migrationBuilder.DropTable(
                name: "SectorCodes");

            migrationBuilder.DropTable(
                name: "Address");

            migrationBuilder.DropTable(
                name: "DataSourceClassifications");

            migrationBuilder.DropTable(
                name: "EnterpriseGroupTypes");

            migrationBuilder.DropTable(
                name: "RegistrationReasons");

            migrationBuilder.DropTable(
                name: "ReorgTypes");

            migrationBuilder.DropTable(
                name: "UnitSizes");

            migrationBuilder.DropTable(
                name: "UnitStatuses");

            migrationBuilder.DropTable(
                name: "Regions");
        }
    }
}
