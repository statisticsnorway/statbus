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
                    IdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ActivityCategoryId = table.Column<int>(type: "integer", nullable: false),
                    ActivityYear = table.Column<int>(type: "integer", nullable: true),
                    ActivityType = table.Column<int>(type: "integer", nullable: false),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: false),
                    UpdatedDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
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
                        name: "FK_Activities_AspNetUsers_UpdatedBy",
                        column: x => x.UpdatedBy,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ActivityCategoryUsers",
                columns: table => new
                {
                    UserId = table.Column<string>(type: "text", nullable: false),
                    ActivityCategoryId = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategoryUsers", x => new { x.UserId, x.ActivityCategoryId });
                    table.ForeignKey(
                        name: "FK_ActivityCategoryUsers_ActivityCategories_ActivityCategoryId",
                        column: x => x.ActivityCategoryId,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityCategoryUsers_AspNetUsers_UserId",
                        column: x => x.UserId,
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
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    AddressPart1 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AddressPart2 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AddressPart3 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    RegionId = table.Column<int>(type: "integer", nullable: false),
                    Latitude = table.Column<double>(type: "double precision", nullable: true),
                    Longitude = table.Column<double>(type: "double precision", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Address", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Address_Regions_RegionId",
                        column: x => x.RegionId,
                        principalTable: "Regions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "UserRegions",
                columns: table => new
                {
                    UserId = table.Column<string>(type: "text", nullable: false),
                    RegionId = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserRegions", x => new { x.UserId, x.RegionId });
                    table.ForeignKey(
                        name: "FK_UserRegions_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_UserRegions_Regions_RegionId",
                        column: x => x.RegionId,
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
                    SizeId = table.Column<int>(type: "integer", nullable: true),
                    DataSourceClassificationId = table.Column<int>(type: "integer", nullable: true),
                    ReorgTypeId = table.Column<int>(type: "integer", nullable: true),
                    ReorgDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    UnitStatusId = table.Column<int>(type: "integer", nullable: true),
                    ForeignParticipationId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroups", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseGroups_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
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
                        name: "FK_EnterpriseGroups_ForeignParticipations_ForeignParticipation~",
                        column: x => x.ForeignParticipationId,
                        principalTable: "ForeignParticipations",
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
                name: "History",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    StartOn = table.Column<DateOnly>(type: "date", nullable: false),
                    StopOn = table.Column<DateOnly>(type: "date", nullable: true),
                    LegalFormId = table.Column<int>(type: "integer", nullable: true),
                    SectorCodeIds = table.Column<int[]>(type: "integer[]", nullable: true),
                    RegionIds = table.Column<int[]>(type: "integer[]", nullable: true),
                    ActivityCategoryIds = table.Column<int[]>(type: "integer[]", nullable: true),
                    SizeId = table.Column<int>(type: "integer", nullable: true),
                    LocalUnitId = table.Column<int>(type: "integer", nullable: true),
                    LegalUnitId = table.Column<int>(type: "integer", nullable: true),
                    EnterpriseUnitId = table.Column<int>(type: "integer", nullable: true),
                    EnterpriseGroupId = table.Column<int>(type: "integer", nullable: true),
                    Name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    ShortName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    TaxRegId = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ExternalId = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ExternalIdType = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    DataSource = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AddressId = table.Column<int>(type: "integer", nullable: true),
                    WebAddress = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    TelephoneNo = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    EmailAddress = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    FreeEconZone = table.Column<bool>(type: "boolean", nullable: false),
                    NumOfPeopleEmp = table.Column<int>(type: "integer", nullable: true),
                    Employees = table.Column<int>(type: "integer", nullable: true),
                    Turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    Classified = table.Column<bool>(type: "boolean", nullable: true),
                    LiqDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LiqReason = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    UserId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    ChangeReason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    EditComment = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    DataSourceClassificationId = table.Column<int>(type: "integer", nullable: true),
                    ReorgTypeId = table.Column<int>(type: "integer", nullable: true),
                    UnitStatusId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_History", x => x.Id);
                    table.ForeignKey(
                        name: "FK_History_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
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
                name: "EnterpriseUnits",
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
                    EnterpriseGroupId = table.Column<int>(type: "integer", nullable: true),
                    EntGroupIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Commercial = table.Column<bool>(type: "boolean", nullable: false),
                    TotalCapital = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    MunCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    StateCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    PrivCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    EntGroupRoleId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseUnits", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_DataSourceClassifications_DataSourceClassif~",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_EnterpriseGroupRoles_EntGroupRoleId",
                        column: x => x.EntGroupRoleId,
                        principalTable: "EnterpriseGroupRoles",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_EnterpriseGroups_EnterpriseGroupId",
                        column: x => x.EnterpriseGroupId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_ForeignParticipations_ForeignParticipationId",
                        column: x => x.ForeignParticipationId,
                        principalTable: "ForeignParticipations",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_LegalForms_LegalFormId",
                        column: x => x.LegalFormId,
                        principalTable: "LegalForms",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_SectorCodes_InstSectorCodeId",
                        column: x => x.InstSectorCodeId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_UnitSizes_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitSizes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_EnterpriseUnits_UnitStatuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "UnitStatuses",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "LegalUnits",
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
                    EnterpriseUnitRegId = table.Column<int>(type: "integer", nullable: true),
                    EntRegIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Market = table.Column<bool>(type: "boolean", nullable: true),
                    TotalCapital = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    MunCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    StateCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    PrivCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LegalUnits", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_LegalUnits_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_DataSourceClassifications_DataSourceClassificati~",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_EnterpriseUnits_EnterpriseUnitRegId",
                        column: x => x.EnterpriseUnitRegId,
                        principalTable: "EnterpriseUnits",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_LegalUnits_ForeignParticipations_ForeignParticipationId",
                        column: x => x.ForeignParticipationId,
                        principalTable: "ForeignParticipations",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_LegalForms_LegalFormId",
                        column: x => x.LegalFormId,
                        principalTable: "LegalForms",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_SectorCodes_InstSectorCodeId",
                        column: x => x.InstSectorCodeId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_UnitSizes_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitSizes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LegalUnits_UnitStatuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "UnitStatuses",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "LocalUnits",
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
                    LegalUnitId = table.Column<int>(type: "integer", nullable: true),
                    LegalUnitIdDate = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LocalUnits", x => x.RegId);
                    table.ForeignKey(
                        name: "FK_LocalUnits_Address_ActualAddressId",
                        column: x => x.ActualAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_Address_AddressId",
                        column: x => x.AddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_Address_PostalAddressId",
                        column: x => x.PostalAddressId,
                        principalTable: "Address",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_DataSourceClassifications_DataSourceClassificati~",
                        column: x => x.DataSourceClassificationId,
                        principalTable: "DataSourceClassifications",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_ForeignParticipations_ForeignParticipationId",
                        column: x => x.ForeignParticipationId,
                        principalTable: "ForeignParticipations",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_LegalForms_LegalFormId",
                        column: x => x.LegalFormId,
                        principalTable: "LegalForms",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_LegalUnits_LegalUnitId",
                        column: x => x.LegalUnitId,
                        principalTable: "LegalUnits",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_LocalUnits_RegistrationReasons_RegistrationReasonId",
                        column: x => x.RegistrationReasonId,
                        principalTable: "RegistrationReasons",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_ReorgTypes_ReorgTypeId",
                        column: x => x.ReorgTypeId,
                        principalTable: "ReorgTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_SectorCodes_InstSectorCodeId",
                        column: x => x.InstSectorCodeId,
                        principalTable: "SectorCodes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_UnitSizes_SizeId",
                        column: x => x.SizeId,
                        principalTable: "UnitSizes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LocalUnits_UnitStatuses_UnitStatusId",
                        column: x => x.UnitStatusId,
                        principalTable: "UnitStatuses",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "ActivityLegalUnits",
                columns: table => new
                {
                    UnitId = table.Column<int>(type: "integer", nullable: false),
                    ActivityId = table.Column<int>(type: "integer", nullable: false),
                    EnterpriseUnitRegId = table.Column<int>(type: "integer", nullable: true),
                    HistoryId = table.Column<int>(type: "integer", nullable: true),
                    LocalUnitRegId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityLegalUnits", x => new { x.UnitId, x.ActivityId });
                    table.ForeignKey(
                        name: "FK_ActivityLegalUnits_Activities_ActivityId",
                        column: x => x.ActivityId,
                        principalTable: "Activities",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityLegalUnits_EnterpriseUnits_EnterpriseUnitRegId",
                        column: x => x.EnterpriseUnitRegId,
                        principalTable: "EnterpriseUnits",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_ActivityLegalUnits_History_HistoryId",
                        column: x => x.HistoryId,
                        principalTable: "History",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_ActivityLegalUnits_LegalUnits_UnitId",
                        column: x => x.UnitId,
                        principalTable: "LegalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityLegalUnits_LocalUnits_LocalUnitRegId",
                        column: x => x.LocalUnitRegId,
                        principalTable: "LocalUnits",
                        principalColumn: "RegId");
                });

            migrationBuilder.CreateTable(
                name: "CountryStatisticalUnits",
                columns: table => new
                {
                    EnterpriseUnitId = table.Column<int>(type: "integer", nullable: false),
                    CountryId = table.Column<int>(type: "integer", nullable: false),
                    LocalUnitId = table.Column<int>(type: "integer", nullable: false),
                    LegalUnitId = table.Column<int>(type: "integer", nullable: false),
                    EnterpriseGroupId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CountryStatisticalUnits", x => new { x.EnterpriseUnitId, x.CountryId });
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnits_Countries_CountryId",
                        column: x => x.CountryId,
                        principalTable: "Countries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnits_EnterpriseGroups_EnterpriseGroupId",
                        column: x => x.EnterpriseGroupId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnits_EnterpriseUnits_EnterpriseUnitId",
                        column: x => x.EnterpriseUnitId,
                        principalTable: "EnterpriseUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnits_LegalUnits_LegalUnitId",
                        column: x => x.LegalUnitId,
                        principalTable: "LegalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_CountryStatisticalUnits_LocalUnits_LocalUnitId",
                        column: x => x.LocalUnitId,
                        principalTable: "LocalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PersonStatisticalUnits",
                columns: table => new
                {
                    EnterpriseUnitId = table.Column<int>(type: "integer", nullable: false),
                    PersonId = table.Column<int>(type: "integer", nullable: false),
                    LocalUnitId = table.Column<int>(type: "integer", nullable: false),
                    LegalUnitId = table.Column<int>(type: "integer", nullable: false),
                    EnterpriseGroupId = table.Column<int>(type: "integer", nullable: true),
                    PersonTypeId = table.Column<int>(type: "integer", nullable: true),
                    HistoryId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PersonStatisticalUnits", x => new { x.EnterpriseUnitId, x.PersonId });
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_EnterpriseGroups_EnterpriseGroupId",
                        column: x => x.EnterpriseGroupId,
                        principalTable: "EnterpriseGroups",
                        principalColumn: "RegId");
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_EnterpriseUnits_EnterpriseUnitId",
                        column: x => x.EnterpriseUnitId,
                        principalTable: "EnterpriseUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_History_HistoryId",
                        column: x => x.HistoryId,
                        principalTable: "History",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_LegalUnits_LegalUnitId",
                        column: x => x.LegalUnitId,
                        principalTable: "LegalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_LocalUnits_LocalUnitId",
                        column: x => x.LocalUnitId,
                        principalTable: "LocalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_PersonTypes_PersonTypeId",
                        column: x => x.PersonTypeId,
                        principalTable: "PersonTypes",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_PersonStatisticalUnits_Persons_PersonId",
                        column: x => x.PersonId,
                        principalTable: "Persons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Activities_ActivityCategoryId",
                table: "Activities",
                column: "ActivityCategoryId");

            migrationBuilder.CreateIndex(
                name: "IX_Activities_UpdatedBy",
                table: "Activities",
                column: "UpdatedBy");

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
                name: "IX_ActivityCategoryUsers_ActivityCategoryId",
                table: "ActivityCategoryUsers",
                column: "ActivityCategoryId");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityLegalUnits_ActivityId",
                table: "ActivityLegalUnits",
                column: "ActivityId");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityLegalUnits_EnterpriseUnitRegId",
                table: "ActivityLegalUnits",
                column: "EnterpriseUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityLegalUnits_HistoryId",
                table: "ActivityLegalUnits",
                column: "HistoryId");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityLegalUnits_LocalUnitRegId",
                table: "ActivityLegalUnits",
                column: "LocalUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_ActivityLegalUnits_UnitId",
                table: "ActivityLegalUnits",
                column: "UnitId");

            migrationBuilder.CreateIndex(
                name: "IX_Address_AddressPart1_AddressPart2_AddressPart3_RegionId_Lat~",
                table: "Address",
                columns: new[] { "AddressPart1", "AddressPart2", "AddressPart3", "RegionId", "Latitude", "Longitude" });

            migrationBuilder.CreateIndex(
                name: "IX_Address_RegionId",
                table: "Address",
                column: "RegionId");

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
                name: "IX_CountryStatisticalUnits_CountryId",
                table: "CountryStatisticalUnits",
                column: "CountryId");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnits_EnterpriseGroupId",
                table: "CountryStatisticalUnits",
                column: "EnterpriseGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnits_LegalUnitId",
                table: "CountryStatisticalUnits",
                column: "LegalUnitId");

            migrationBuilder.CreateIndex(
                name: "IX_CountryStatisticalUnits_LocalUnitId",
                table: "CountryStatisticalUnits",
                column: "LocalUnitId");

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
                name: "IX_EnterpriseGroups_ForeignParticipationId",
                table: "EnterpriseGroups",
                column: "ForeignParticipationId");

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
                name: "IX_EnterpriseGroupTypes_Code",
                table: "EnterpriseGroupTypes",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_ActualAddressId",
                table: "EnterpriseUnits",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_AddressId",
                table: "EnterpriseUnits",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_DataSourceClassificationId",
                table: "EnterpriseUnits",
                column: "DataSourceClassificationId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_EnterpriseGroupId",
                table: "EnterpriseUnits",
                column: "EnterpriseGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_EntGroupRoleId",
                table: "EnterpriseUnits",
                column: "EntGroupRoleId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_ForeignParticipationId",
                table: "EnterpriseUnits",
                column: "ForeignParticipationId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_InstSectorCodeId",
                table: "EnterpriseUnits",
                column: "InstSectorCodeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_LegalFormId",
                table: "EnterpriseUnits",
                column: "LegalFormId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_Name",
                table: "EnterpriseUnits",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_PostalAddressId",
                table: "EnterpriseUnits",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_RegistrationReasonId",
                table: "EnterpriseUnits",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_ReorgTypeId",
                table: "EnterpriseUnits",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_ShortName_RegId_StatId_TaxRegId",
                table: "EnterpriseUnits",
                columns: new[] { "ShortName", "RegId", "StatId", "TaxRegId" });

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_SizeId",
                table: "EnterpriseUnits",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_StartPeriod",
                table: "EnterpriseUnits",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_StatId",
                table: "EnterpriseUnits",
                column: "StatId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseUnits_UnitStatusId",
                table: "EnterpriseUnits",
                column: "UnitStatusId");

            migrationBuilder.CreateIndex(
                name: "IX_ForeignParticipations_Code",
                table: "ForeignParticipations",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_History_AddressId",
                table: "History",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_History_Name",
                table: "History",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_LegalForms_Code",
                table: "LegalForms",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_ActualAddressId",
                table: "LegalUnits",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_AddressId",
                table: "LegalUnits",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_DataSourceClassificationId",
                table: "LegalUnits",
                column: "DataSourceClassificationId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_EnterpriseUnitRegId",
                table: "LegalUnits",
                column: "EnterpriseUnitRegId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_ForeignParticipationId",
                table: "LegalUnits",
                column: "ForeignParticipationId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_InstSectorCodeId",
                table: "LegalUnits",
                column: "InstSectorCodeId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_LegalFormId",
                table: "LegalUnits",
                column: "LegalFormId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_Name",
                table: "LegalUnits",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_PostalAddressId",
                table: "LegalUnits",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_RegistrationReasonId",
                table: "LegalUnits",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_ReorgTypeId",
                table: "LegalUnits",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_ShortName_RegId_StatId_TaxRegId",
                table: "LegalUnits",
                columns: new[] { "ShortName", "RegId", "StatId", "TaxRegId" });

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_SizeId",
                table: "LegalUnits",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_StartPeriod",
                table: "LegalUnits",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_StatId",
                table: "LegalUnits",
                column: "StatId");

            migrationBuilder.CreateIndex(
                name: "IX_LegalUnits_UnitStatusId",
                table: "LegalUnits",
                column: "UnitStatusId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_ActualAddressId",
                table: "LocalUnits",
                column: "ActualAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_AddressId",
                table: "LocalUnits",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_DataSourceClassificationId",
                table: "LocalUnits",
                column: "DataSourceClassificationId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_ForeignParticipationId",
                table: "LocalUnits",
                column: "ForeignParticipationId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_InstSectorCodeId",
                table: "LocalUnits",
                column: "InstSectorCodeId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_LegalFormId",
                table: "LocalUnits",
                column: "LegalFormId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_LegalUnitId",
                table: "LocalUnits",
                column: "LegalUnitId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_Name",
                table: "LocalUnits",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_PostalAddressId",
                table: "LocalUnits",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_RegistrationReasonId",
                table: "LocalUnits",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_ReorgTypeId",
                table: "LocalUnits",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_ShortName_RegId_StatId_TaxRegId",
                table: "LocalUnits",
                columns: new[] { "ShortName", "RegId", "StatId", "TaxRegId" });

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_SizeId",
                table: "LocalUnits",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_StartPeriod",
                table: "LocalUnits",
                column: "StartPeriod");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_StatId",
                table: "LocalUnits",
                column: "StatId");

            migrationBuilder.CreateIndex(
                name: "IX_LocalUnits_UnitStatusId",
                table: "LocalUnits",
                column: "UnitStatusId");

            migrationBuilder.CreateIndex(
                name: "IX_Persons_CountryId",
                table: "Persons",
                column: "CountryId");

            migrationBuilder.CreateIndex(
                name: "IX_Persons_GivenName_Surname",
                table: "Persons",
                columns: new[] { "GivenName", "Surname" });

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_EnterpriseGroupId",
                table: "PersonStatisticalUnits",
                column: "EnterpriseGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_EnterpriseUnitId",
                table: "PersonStatisticalUnits",
                column: "EnterpriseUnitId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_HistoryId",
                table: "PersonStatisticalUnits",
                column: "HistoryId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_LegalUnitId",
                table: "PersonStatisticalUnits",
                column: "LegalUnitId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_LocalUnitId",
                table: "PersonStatisticalUnits",
                column: "LocalUnitId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_PersonId",
                table: "PersonStatisticalUnits",
                column: "PersonId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_PersonTypeId_LocalUnitId_LegalUnitId~",
                table: "PersonStatisticalUnits",
                columns: new[] { "PersonTypeId", "LocalUnitId", "LegalUnitId", "EnterpriseUnitId", "PersonId" },
                unique: true);

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
                name: "IX_UserRegions_RegionId",
                table: "UserRegions",
                column: "RegionId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ActivityCategoryUsers");

            migrationBuilder.DropTable(
                name: "ActivityLegalUnits");

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
                name: "CountryStatisticalUnits");

            migrationBuilder.DropTable(
                name: "CustomAnalysisChecks");

            migrationBuilder.DropTable(
                name: "DataUploadingLogs");

            migrationBuilder.DropTable(
                name: "DictionaryVersions");

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
                name: "Activities");

            migrationBuilder.DropTable(
                name: "AnalysisQueues");

            migrationBuilder.DropTable(
                name: "AspNetRoles");

            migrationBuilder.DropTable(
                name: "DataSourceQueues");

            migrationBuilder.DropTable(
                name: "History");

            migrationBuilder.DropTable(
                name: "LocalUnits");

            migrationBuilder.DropTable(
                name: "PersonTypes");

            migrationBuilder.DropTable(
                name: "Persons");

            migrationBuilder.DropTable(
                name: "ActivityCategories");

            migrationBuilder.DropTable(
                name: "DataSourceUploads");

            migrationBuilder.DropTable(
                name: "LegalUnits");

            migrationBuilder.DropTable(
                name: "Countries");

            migrationBuilder.DropTable(
                name: "AspNetUsers");

            migrationBuilder.DropTable(
                name: "EnterpriseUnits");

            migrationBuilder.DropTable(
                name: "EnterpriseGroupRoles");

            migrationBuilder.DropTable(
                name: "EnterpriseGroups");

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
                name: "ForeignParticipations");

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
