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
                name: "activity_category",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    section = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    parent_id = table.Column<int>(type: "integer", nullable: true),
                    dic_parent_id = table.Column<int>(type: "integer", nullable: true),
                    version_id = table.Column<int>(type: "integer", nullable: false),
                    activity_category_level = table.Column<int>(type: "integer", nullable: true),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_activity_category", x => x.id);
                    table.ForeignKey(
                        name: "fk_activity_category_activity_category_parent_id",
                        column: x => x.parent_id,
                        principalTable: "activity_category",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoles",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    access_to_system_functions = table.Column<string>(type: "text", nullable: true),
                    standard_data_access = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    sql_wallet_user = table.Column<string>(type: "text", nullable: true),
                    name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    normalized_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    concurrency_stamp = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_roles", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUsers",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: true),
                    description = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    data_access = table.Column<string>(type: "text", nullable: true),
                    creation_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    suspension_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    user_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    normalized_user_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    normalized_email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    email_confirmed = table.Column<bool>(type: "boolean", nullable: false),
                    password_hash = table.Column<string>(type: "text", nullable: true),
                    security_stamp = table.Column<string>(type: "text", nullable: true),
                    concurrency_stamp = table.Column<string>(type: "text", nullable: true),
                    phone_number = table.Column<string>(type: "text", nullable: true),
                    phone_number_confirmed = table.Column<bool>(type: "boolean", nullable: false),
                    two_factor_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    lockout_end = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    lockout_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    access_failed_count = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "country",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    iso_code = table.Column<string>(type: "text", nullable: true),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_country", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "custom_analysis_check",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    query = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    target_unit_types = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_custom_analysis_check", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "data_source_classification",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_data_source_classification", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "dictionary_version",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    version_id = table.Column<int>(type: "integer", nullable: false),
                    version_name = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_dictionary_version", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "enterprise_group_role",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_enterprise_group_role", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "enterprise_group_type",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_enterprise_group_type", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "foreign_participation",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_foreign_participation", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "legal_form",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_legal_form", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "person_type",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_person_type", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "postal_index",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_postal_index", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "region",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    adminstrative_center = table.Column<string>(type: "text", nullable: true),
                    parent_id = table.Column<int>(type: "integer", nullable: true),
                    full_path = table.Column<string>(type: "text", nullable: true),
                    full_path_language1 = table.Column<string>(type: "text", nullable: true),
                    full_path_language2 = table.Column<string>(type: "text", nullable: true),
                    region_level = table.Column<int>(type: "integer", nullable: true),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_region", x => x.id);
                    table.ForeignKey(
                        name: "fk_region_region_parent_id",
                        column: x => x.parent_id,
                        principalTable: "region",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "registration_reason",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_registration_reason", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "reorg_type",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_reorg_type", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "report_tree",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    title = table.Column<string>(type: "text", nullable: true),
                    type = table.Column<string>(type: "text", nullable: true),
                    report_id = table.Column<int>(type: "integer", nullable: true),
                    parent_node_id = table.Column<int>(type: "integer", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    resource_group = table.Column<string>(type: "text", nullable: true),
                    report_url = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_report_tree", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "sector_code",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    parent_id = table.Column<int>(type: "integer", nullable: true),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sector_code", x => x.id);
                    table.ForeignKey(
                        name: "fk_sector_code_sector_code_parent_id",
                        column: x => x.parent_id,
                        principalTable: "sector_code",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "unit_size",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    code = table.Column<int>(type: "integer", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_unit_size", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "unit_status",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    name_language1 = table.Column<string>(type: "text", nullable: true),
                    name_language2 = table.Column<string>(type: "text", nullable: true),
                    code = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_unit_status", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoleClaims",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    role_id = table.Column<string>(type: "text", nullable: false),
                    claim_type = table.Column<string>(type: "text", nullable: true),
                    claim_value = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_role_claims", x => x.id);
                    table.ForeignKey(
                        name: "fk_asp_net_role_claims_asp_net_roles_role_id",
                        column: x => x.role_id,
                        principalTable: "AspNetRoles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "activity",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    activity_category_id = table.Column<int>(type: "integer", nullable: false),
                    activity_year = table.Column<int>(type: "integer", nullable: true),
                    activity_type = table.Column<int>(type: "integer", nullable: false),
                    employees = table.Column<int>(type: "integer", nullable: true),
                    turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    updated_by = table.Column<string>(type: "text", nullable: false),
                    updated_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_activity", x => x.id);
                    table.ForeignKey(
                        name: "fk_activity_activity_category_activity_category_id",
                        column: x => x.activity_category_id,
                        principalTable: "activity_category",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_activity_user_updated_by_user_id",
                        column: x => x.updated_by,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "activity_category_user",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    activity_category_id = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_activity_category_user", x => new { x.user_id, x.activity_category_id });
                    table.ForeignKey(
                        name: "fk_activity_category_user_activity_category_activity_category_",
                        column: x => x.activity_category_id,
                        principalTable: "activity_category",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_activity_category_user_user_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "analysis_queue",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    user_start_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    user_end_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    comment = table.Column<string>(type: "text", nullable: true),
                    server_start_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    server_end_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_analysis_queue", x => x.id);
                    table.ForeignKey(
                        name: "fk_analysis_queue_user_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserClaims",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    claim_type = table.Column<string>(type: "text", nullable: true),
                    claim_value = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_claims", x => x.id);
                    table.ForeignKey(
                        name: "fk_asp_net_user_claims_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserLogins",
                columns: table => new
                {
                    login_provider = table.Column<string>(type: "text", nullable: false),
                    provider_key = table.Column<string>(type: "text", nullable: false),
                    provider_display_name = table.Column<string>(type: "text", nullable: true),
                    user_id = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_logins", x => new { x.login_provider, x.provider_key });
                    table.ForeignKey(
                        name: "fk_asp_net_user_logins_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserRoles",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    role_id = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_roles", x => new { x.user_id, x.role_id });
                    table.ForeignKey(
                        name: "fk_asp_net_user_roles_asp_net_roles_role_id",
                        column: x => x.role_id,
                        principalTable: "AspNetRoles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_asp_net_user_roles_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserTokens",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    login_provider = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    value = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_tokens", x => new { x.user_id, x.login_provider, x.name });
                    table.ForeignKey(
                        name: "fk_asp_net_user_tokens_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "data_source",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    user_id = table.Column<string>(type: "text", nullable: true),
                    priority = table.Column<int>(type: "integer", nullable: false),
                    allowed_operations = table.Column<int>(type: "integer", nullable: false),
                    attributes_to_check = table.Column<string>(type: "text", nullable: true),
                    original_csv_attributes = table.Column<string>(type: "text", nullable: true),
                    stat_unit_type = table.Column<int>(type: "integer", nullable: false),
                    restrictions = table.Column<string>(type: "text", nullable: true),
                    variables_mapping = table.Column<string>(type: "text", nullable: true),
                    csv_delimiter = table.Column<string>(type: "text", nullable: true),
                    csv_skip_count = table.Column<int>(type: "integer", nullable: false),
                    data_source_upload_type = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_data_source", x => x.id);
                    table.ForeignKey(
                        name: "fk_data_source_user_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "sample_frame",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    predicate = table.Column<string>(type: "text", nullable: false),
                    fields = table.Column<string>(type: "text", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    file_path = table.Column<string>(type: "text", nullable: true),
                    generated_date_time = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    creation_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    editing_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sample_frame", x => x.id);
                    table.ForeignKey(
                        name: "fk_sample_frame_user_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "person",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    given_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    personal_id = table.Column<string>(type: "text", nullable: true),
                    surname = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    middle_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    birth_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    sex = table.Column<byte>(type: "smallint", nullable: true),
                    country_id = table.Column<int>(type: "integer", nullable: true),
                    phone_number = table.Column<string>(type: "text", nullable: true),
                    phone_number1 = table.Column<string>(type: "text", nullable: true),
                    address = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_person", x => x.id);
                    table.ForeignKey(
                        name: "fk_person_country_country_id",
                        column: x => x.country_id,
                        principalTable: "country",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "address",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    address_part1 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    address_part2 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    address_part3 = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    region_id = table.Column<int>(type: "integer", nullable: false),
                    latitude = table.Column<double>(type: "double precision", nullable: true),
                    longitude = table.Column<double>(type: "double precision", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_address", x => x.id);
                    table.ForeignKey(
                        name: "fk_address_region_region_id",
                        column: x => x.region_id,
                        principalTable: "region",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_region",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    region_id = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_region", x => new { x.user_id, x.region_id });
                    table.ForeignKey(
                        name: "fk_user_region_region_region_id",
                        column: x => x.region_id,
                        principalTable: "region",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_user_region_user_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "analysis_log",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    analysis_queue_id = table.Column<int>(type: "integer", nullable: false),
                    analyzed_unit_id = table.Column<int>(type: "integer", nullable: false),
                    analyzed_unit_type = table.Column<int>(type: "integer", nullable: false),
                    issued_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    resolved_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    summary_messages = table.Column<string>(type: "text", nullable: true),
                    error_values = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_analysis_log", x => x.id);
                    table.ForeignKey(
                        name: "fk_analysis_log_analysis_queue_analysis_queue_id",
                        column: x => x.analysis_queue_id,
                        principalTable: "analysis_queue",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "data_source_queue",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    start_import_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    end_import_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    data_source_path = table.Column<string>(type: "text", nullable: false),
                    data_source_file_name = table.Column<string>(type: "text", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<int>(type: "integer", nullable: false),
                    note = table.Column<string>(type: "text", nullable: true),
                    data_source_id = table.Column<int>(type: "integer", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: true),
                    skip_lines_count = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_data_source_queue", x => x.id);
                    table.ForeignKey(
                        name: "fk_data_source_queue_data_source_data_source_id",
                        column: x => x.data_source_id,
                        principalTable: "data_source",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_data_source_queue_user_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "enterprise_group",
                columns: table => new
                {
                    reg_id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    reg_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    stat_id = table.Column<string>(type: "text", nullable: true),
                    stat_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    short_name = table.Column<string>(type: "text", nullable: true),
                    registration_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    registration_reason_id = table.Column<int>(type: "integer", nullable: true),
                    tax_reg_id = table.Column<string>(type: "text", nullable: true),
                    tax_reg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    external_id = table.Column<string>(type: "text", nullable: true),
                    external_id_type = table.Column<string>(type: "text", nullable: true),
                    external_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    data_source = table.Column<string>(type: "text", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    address_id = table.Column<int>(type: "integer", nullable: true),
                    actual_address_id = table.Column<int>(type: "integer", nullable: true),
                    postal_address_id = table.Column<int>(type: "integer", nullable: true),
                    ent_group_type_id = table.Column<int>(type: "integer", nullable: true),
                    num_of_people_emp = table.Column<int>(type: "integer", nullable: true),
                    telephone_no = table.Column<string>(type: "text", nullable: true),
                    email_address = table.Column<string>(type: "text", nullable: true),
                    web_address = table.Column<string>(type: "text", nullable: true),
                    liq_date_start = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    liq_date_end = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reorg_type_code = table.Column<string>(type: "text", nullable: true),
                    reorg_references = table.Column<string>(type: "text", nullable: true),
                    contact_person = table.Column<string>(type: "text", nullable: true),
                    start_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    end_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    liq_reason = table.Column<string>(type: "text", nullable: true),
                    suspension_start = table.Column<string>(type: "text", nullable: true),
                    suspension_end = table.Column<string>(type: "text", nullable: true),
                    employees = table.Column<int>(type: "integer", nullable: true),
                    employees_year = table.Column<int>(type: "integer", nullable: true),
                    employees_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    turnover_year = table.Column<int>(type: "integer", nullable: true),
                    turnover_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    status_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    notes = table.Column<string>(type: "text", nullable: true),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    change_reason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    edit_comment = table.Column<string>(type: "text", nullable: true),
                    size_id = table.Column<int>(type: "integer", nullable: true),
                    data_source_classification_id = table.Column<int>(type: "integer", nullable: true),
                    reorg_type_id = table.Column<int>(type: "integer", nullable: true),
                    reorg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    unit_status_id = table.Column<int>(type: "integer", nullable: true),
                    foreign_participation_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_enterprise_group", x => x.reg_id);
                    table.ForeignKey(
                        name: "fk_enterprise_group_address_actual_address_id",
                        column: x => x.actual_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_address_address_id",
                        column: x => x.address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_address_postal_address_id",
                        column: x => x.postal_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_data_source_classification_data_source_cla",
                        column: x => x.data_source_classification_id,
                        principalTable: "data_source_classification",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_enterprise_group_type_ent_group_type_id",
                        column: x => x.ent_group_type_id,
                        principalTable: "enterprise_group_type",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_foreign_participation_foreign_participatio",
                        column: x => x.foreign_participation_id,
                        principalTable: "foreign_participation",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_registration_reason_registration_reason_id",
                        column: x => x.registration_reason_id,
                        principalTable: "registration_reason",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_reorg_type_reorg_type_id",
                        column: x => x.reorg_type_id,
                        principalTable: "reorg_type",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_unit_size_size_id",
                        column: x => x.size_id,
                        principalTable: "unit_size",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_group_unit_status_unit_status_id",
                        column: x => x.unit_status_id,
                        principalTable: "unit_status",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "history",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    start_on = table.Column<DateOnly>(type: "date", nullable: false),
                    stop_on = table.Column<DateOnly>(type: "date", nullable: true),
                    legal_form_id = table.Column<int>(type: "integer", nullable: true),
                    sector_code_ids = table.Column<int[]>(type: "integer[]", nullable: true),
                    region_ids = table.Column<int[]>(type: "integer[]", nullable: true),
                    activity_category_ids = table.Column<int[]>(type: "integer[]", nullable: true),
                    size_id = table.Column<int>(type: "integer", nullable: true),
                    local_unit_id = table.Column<int>(type: "integer", nullable: true),
                    legal_unit_id = table.Column<int>(type: "integer", nullable: true),
                    enterprise_unit_id = table.Column<int>(type: "integer", nullable: true),
                    enterprise_group_id = table.Column<int>(type: "integer", nullable: true),
                    name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    short_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    tax_reg_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    external_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    external_id_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    data_source = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    address_id = table.Column<int>(type: "integer", nullable: true),
                    web_address = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    telephone_no = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    email_address = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    free_econ_zone = table.Column<bool>(type: "boolean", nullable: false),
                    num_of_people_emp = table.Column<int>(type: "integer", nullable: true),
                    employees = table.Column<int>(type: "integer", nullable: true),
                    turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    classified = table.Column<bool>(type: "boolean", nullable: true),
                    liq_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    liq_reason = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    user_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    change_reason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    edit_comment = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    data_source_classification_id = table.Column<int>(type: "integer", nullable: true),
                    reorg_type_id = table.Column<int>(type: "integer", nullable: true),
                    unit_status_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_history", x => x.id);
                    table.ForeignKey(
                        name: "fk_history_address_address_id",
                        column: x => x.address_id,
                        principalTable: "address",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "data_uploading_log",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    start_import_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    end_import_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    target_stat_id = table.Column<string>(type: "text", nullable: true),
                    stat_unit_name = table.Column<string>(type: "text", nullable: true),
                    serialized_unit = table.Column<string>(type: "text", nullable: true),
                    serialized_raw_unit = table.Column<string>(type: "text", nullable: true),
                    data_source_queue_id = table.Column<int>(type: "integer", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    note = table.Column<string>(type: "text", nullable: true),
                    errors = table.Column<string>(type: "text", nullable: true),
                    summary = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_data_uploading_log", x => x.id);
                    table.ForeignKey(
                        name: "fk_data_uploading_log_data_source_queue_data_source_queue_id",
                        column: x => x.data_source_queue_id,
                        principalTable: "data_source_queue",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "enterprise_unit",
                columns: table => new
                {
                    reg_id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    reg_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    stat_id = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    stat_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    short_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    parent_org_link = table.Column<int>(type: "integer", nullable: true),
                    tax_reg_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    tax_reg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    registration_reason_id = table.Column<int>(type: "integer", nullable: true),
                    registration_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    external_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    external_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    external_id_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    data_source = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    address_id = table.Column<int>(type: "integer", nullable: true),
                    web_address = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    telephone_no = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    email_address = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    actual_address_id = table.Column<int>(type: "integer", nullable: true),
                    postal_address_id = table.Column<int>(type: "integer", nullable: true),
                    free_econ_zone = table.Column<bool>(type: "boolean", nullable: false),
                    num_of_people_emp = table.Column<int>(type: "integer", nullable: true),
                    employees = table.Column<int>(type: "integer", nullable: true),
                    employees_year = table.Column<int>(type: "integer", nullable: true),
                    employees_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    turnover_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    turnover_year = table.Column<int>(type: "integer", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    classified = table.Column<bool>(type: "boolean", nullable: true),
                    status_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ref_no = table.Column<string>(type: "character varying(25)", maxLength: 25, nullable: true),
                    inst_sector_code_id = table.Column<int>(type: "integer", nullable: true),
                    legal_form_id = table.Column<int>(type: "integer", nullable: true),
                    liq_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    liq_reason = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    suspension_start = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    suspension_end = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reorg_type_code = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    reorg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reorg_references = table.Column<int>(type: "integer", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    start_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    end_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    user_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    change_reason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    edit_comment = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    size_id = table.Column<int>(type: "integer", nullable: true),
                    foreign_participation_id = table.Column<int>(type: "integer", nullable: true),
                    data_source_classification_id = table.Column<int>(type: "integer", nullable: true),
                    reorg_type_id = table.Column<int>(type: "integer", nullable: true),
                    unit_status_id = table.Column<int>(type: "integer", nullable: true),
                    enterprise_group_id = table.Column<int>(type: "integer", nullable: true),
                    ent_group_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    commercial = table.Column<bool>(type: "boolean", nullable: false),
                    TotalCapital = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    MunCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    StateCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    PrivCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ent_group_role_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_enterprise_unit", x => x.reg_id);
                    table.ForeignKey(
                        name: "fk_enterprise_unit_address_actual_address_id",
                        column: x => x.actual_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_address_address_id",
                        column: x => x.address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_address_postal_address_id",
                        column: x => x.postal_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_data_source_classification_data_source_clas",
                        column: x => x.data_source_classification_id,
                        principalTable: "data_source_classification",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_enterprise_group_enterprise_group_id",
                        column: x => x.enterprise_group_id,
                        principalTable: "enterprise_group",
                        principalColumn: "reg_id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_enterprise_group_role_ent_group_role_id",
                        column: x => x.ent_group_role_id,
                        principalTable: "enterprise_group_role",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_foreign_participation_foreign_participation",
                        column: x => x.foreign_participation_id,
                        principalTable: "foreign_participation",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_legal_form_legal_form_id",
                        column: x => x.legal_form_id,
                        principalTable: "legal_form",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_registration_reason_registration_reason_id",
                        column: x => x.registration_reason_id,
                        principalTable: "registration_reason",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_reorg_type_reorg_type_id",
                        column: x => x.reorg_type_id,
                        principalTable: "reorg_type",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_sector_code_inst_sector_code_id",
                        column: x => x.inst_sector_code_id,
                        principalTable: "sector_code",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_unit_size_size_id",
                        column: x => x.size_id,
                        principalTable: "unit_size",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_enterprise_unit_unit_status_unit_status_id",
                        column: x => x.unit_status_id,
                        principalTable: "unit_status",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "legal_unit",
                columns: table => new
                {
                    reg_id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    reg_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    stat_id = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    stat_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    short_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    parent_org_link = table.Column<int>(type: "integer", nullable: true),
                    tax_reg_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    tax_reg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    registration_reason_id = table.Column<int>(type: "integer", nullable: true),
                    registration_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    external_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    external_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    external_id_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    data_source = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    address_id = table.Column<int>(type: "integer", nullable: true),
                    web_address = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    telephone_no = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    email_address = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    actual_address_id = table.Column<int>(type: "integer", nullable: true),
                    postal_address_id = table.Column<int>(type: "integer", nullable: true),
                    free_econ_zone = table.Column<bool>(type: "boolean", nullable: false),
                    num_of_people_emp = table.Column<int>(type: "integer", nullable: true),
                    employees = table.Column<int>(type: "integer", nullable: true),
                    employees_year = table.Column<int>(type: "integer", nullable: true),
                    employees_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    turnover_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    turnover_year = table.Column<int>(type: "integer", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    classified = table.Column<bool>(type: "boolean", nullable: true),
                    status_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ref_no = table.Column<string>(type: "character varying(25)", maxLength: 25, nullable: true),
                    inst_sector_code_id = table.Column<int>(type: "integer", nullable: true),
                    legal_form_id = table.Column<int>(type: "integer", nullable: true),
                    liq_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    liq_reason = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    suspension_start = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    suspension_end = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reorg_type_code = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    reorg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reorg_references = table.Column<int>(type: "integer", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    start_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    end_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    user_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    change_reason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    edit_comment = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    size_id = table.Column<int>(type: "integer", nullable: true),
                    foreign_participation_id = table.Column<int>(type: "integer", nullable: true),
                    data_source_classification_id = table.Column<int>(type: "integer", nullable: true),
                    reorg_type_id = table.Column<int>(type: "integer", nullable: true),
                    unit_status_id = table.Column<int>(type: "integer", nullable: true),
                    enterprise_unit_reg_id = table.Column<int>(type: "integer", nullable: true),
                    ent_reg_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    market = table.Column<bool>(type: "boolean", nullable: true),
                    TotalCapital = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    MunCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    StateCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    PrivCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalShare = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ForeignCapitalCurrency = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_legal_unit", x => x.reg_id);
                    table.ForeignKey(
                        name: "fk_legal_unit_address_actual_address_id",
                        column: x => x.actual_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_address_address_id",
                        column: x => x.address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_address_postal_address_id",
                        column: x => x.postal_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_data_source_classification_data_source_classific",
                        column: x => x.data_source_classification_id,
                        principalTable: "data_source_classification",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_enterprise_unit_enterprise_unit_temp_id",
                        column: x => x.enterprise_unit_reg_id,
                        principalTable: "enterprise_unit",
                        principalColumn: "reg_id");
                    table.ForeignKey(
                        name: "fk_legal_unit_foreign_participation_foreign_participation_id",
                        column: x => x.foreign_participation_id,
                        principalTable: "foreign_participation",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_legal_form_legal_form_id",
                        column: x => x.legal_form_id,
                        principalTable: "legal_form",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_registration_reason_registration_reason_id",
                        column: x => x.registration_reason_id,
                        principalTable: "registration_reason",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_reorg_type_reorg_type_id",
                        column: x => x.reorg_type_id,
                        principalTable: "reorg_type",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_sector_code_inst_sector_code_id",
                        column: x => x.inst_sector_code_id,
                        principalTable: "sector_code",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_unit_size_size_id",
                        column: x => x.size_id,
                        principalTable: "unit_size",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_legal_unit_unit_status_unit_status_id",
                        column: x => x.unit_status_id,
                        principalTable: "unit_status",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "local_unit",
                columns: table => new
                {
                    reg_id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    reg_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    stat_id = table.Column<string>(type: "character varying(15)", maxLength: 15, nullable: true),
                    stat_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    name = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: true),
                    short_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    parent_org_link = table.Column<int>(type: "integer", nullable: true),
                    tax_reg_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    tax_reg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    registration_reason_id = table.Column<int>(type: "integer", nullable: true),
                    registration_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    external_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    external_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    external_id_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    data_source = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    address_id = table.Column<int>(type: "integer", nullable: true),
                    web_address = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    telephone_no = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    email_address = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    actual_address_id = table.Column<int>(type: "integer", nullable: true),
                    postal_address_id = table.Column<int>(type: "integer", nullable: true),
                    free_econ_zone = table.Column<bool>(type: "boolean", nullable: false),
                    num_of_people_emp = table.Column<int>(type: "integer", nullable: true),
                    employees = table.Column<int>(type: "integer", nullable: true),
                    employees_year = table.Column<int>(type: "integer", nullable: true),
                    employees_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    turnover = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    turnover_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    turnover_year = table.Column<int>(type: "integer", nullable: true),
                    notes = table.Column<string>(type: "text", nullable: true),
                    classified = table.Column<bool>(type: "boolean", nullable: true),
                    status_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ref_no = table.Column<string>(type: "character varying(25)", maxLength: 25, nullable: true),
                    inst_sector_code_id = table.Column<int>(type: "integer", nullable: true),
                    legal_form_id = table.Column<int>(type: "integer", nullable: true),
                    liq_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    liq_reason = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    suspension_start = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    suspension_end = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reorg_type_code = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    reorg_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    reorg_references = table.Column<int>(type: "integer", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    start_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    end_period = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    user_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    change_reason = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    edit_comment = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    size_id = table.Column<int>(type: "integer", nullable: true),
                    foreign_participation_id = table.Column<int>(type: "integer", nullable: true),
                    data_source_classification_id = table.Column<int>(type: "integer", nullable: true),
                    reorg_type_id = table.Column<int>(type: "integer", nullable: true),
                    unit_status_id = table.Column<int>(type: "integer", nullable: true),
                    legal_unit_id = table.Column<int>(type: "integer", nullable: true),
                    legal_unit_id_date = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_local_unit", x => x.reg_id);
                    table.ForeignKey(
                        name: "fk_local_unit_address_actual_address_id",
                        column: x => x.actual_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_address_address_id",
                        column: x => x.address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_address_postal_address_id",
                        column: x => x.postal_address_id,
                        principalTable: "address",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_data_source_classification_data_source_classific",
                        column: x => x.data_source_classification_id,
                        principalTable: "data_source_classification",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_foreign_participation_foreign_participation_id",
                        column: x => x.foreign_participation_id,
                        principalTable: "foreign_participation",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_legal_form_legal_form_id",
                        column: x => x.legal_form_id,
                        principalTable: "legal_form",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_legal_unit_legal_unit_id",
                        column: x => x.legal_unit_id,
                        principalTable: "legal_unit",
                        principalColumn: "reg_id");
                    table.ForeignKey(
                        name: "fk_local_unit_registration_reason_registration_reason_id",
                        column: x => x.registration_reason_id,
                        principalTable: "registration_reason",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_reorg_type_reorg_type_id",
                        column: x => x.reorg_type_id,
                        principalTable: "reorg_type",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_sector_code_inst_sector_code_id",
                        column: x => x.inst_sector_code_id,
                        principalTable: "sector_code",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_unit_size_size_id",
                        column: x => x.size_id,
                        principalTable: "unit_size",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_local_unit_unit_status_unit_status_id",
                        column: x => x.unit_status_id,
                        principalTable: "unit_status",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "activity_legal_unit",
                columns: table => new
                {
                    unit_id = table.Column<int>(type: "integer", nullable: false),
                    activity_id = table.Column<int>(type: "integer", nullable: false),
                    enterprise_unit_reg_id = table.Column<int>(type: "integer", nullable: true),
                    history_id = table.Column<int>(type: "integer", nullable: true),
                    local_unit_reg_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_activity_legal_unit", x => new { x.unit_id, x.activity_id });
                    table.ForeignKey(
                        name: "fk_activity_legal_unit_activity_activity_id",
                        column: x => x.activity_id,
                        principalTable: "activity",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_activity_legal_unit_enterprise_unit_enterprise_unit_temp_id3",
                        column: x => x.enterprise_unit_reg_id,
                        principalTable: "enterprise_unit",
                        principalColumn: "reg_id");
                    table.ForeignKey(
                        name: "fk_activity_legal_unit_history_history_id",
                        column: x => x.history_id,
                        principalTable: "history",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_activity_legal_unit_legal_unit_unit_id",
                        column: x => x.unit_id,
                        principalTable: "legal_unit",
                        principalColumn: "reg_id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_activity_legal_unit_local_unit_local_unit_temp_id2",
                        column: x => x.local_unit_reg_id,
                        principalTable: "local_unit",
                        principalColumn: "reg_id");
                });

            migrationBuilder.CreateTable(
                name: "country_for_unit",
                columns: table => new
                {
                    enterprise_unit_id = table.Column<int>(type: "integer", nullable: false),
                    country_id = table.Column<int>(type: "integer", nullable: false),
                    local_unit_id = table.Column<int>(type: "integer", nullable: false),
                    legal_unit_id = table.Column<int>(type: "integer", nullable: false),
                    enterprise_group_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_country_for_unit", x => new { x.enterprise_unit_id, x.country_id });
                    table.ForeignKey(
                        name: "fk_country_for_unit_country_country_id",
                        column: x => x.country_id,
                        principalTable: "country",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_country_for_unit_enterprise_group_enterprise_group_id",
                        column: x => x.enterprise_group_id,
                        principalTable: "enterprise_group",
                        principalColumn: "reg_id");
                    table.ForeignKey(
                        name: "fk_country_for_unit_enterprise_unit_enterprise_unit_id",
                        column: x => x.enterprise_unit_id,
                        principalTable: "enterprise_unit",
                        principalColumn: "reg_id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_country_for_unit_legal_unit_legal_unit_id",
                        column: x => x.legal_unit_id,
                        principalTable: "legal_unit",
                        principalColumn: "reg_id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_country_for_unit_local_unit_local_unit_id",
                        column: x => x.local_unit_id,
                        principalTable: "local_unit",
                        principalColumn: "reg_id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "person_for_unit",
                columns: table => new
                {
                    enterprise_unit_id = table.Column<int>(type: "integer", nullable: false),
                    person_id = table.Column<int>(type: "integer", nullable: false),
                    local_unit_id = table.Column<int>(type: "integer", nullable: false),
                    legal_unit_id = table.Column<int>(type: "integer", nullable: false),
                    enterprise_group_id = table.Column<int>(type: "integer", nullable: true),
                    person_type_id = table.Column<int>(type: "integer", nullable: true),
                    history_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_person_for_unit", x => new { x.enterprise_unit_id, x.person_id });
                    table.ForeignKey(
                        name: "fk_person_for_unit_enterprise_group_enterprise_group_id",
                        column: x => x.enterprise_group_id,
                        principalTable: "enterprise_group",
                        principalColumn: "reg_id");
                    table.ForeignKey(
                        name: "fk_person_for_unit_enterprise_unit_enterprise_unit_id",
                        column: x => x.enterprise_unit_id,
                        principalTable: "enterprise_unit",
                        principalColumn: "reg_id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_person_for_unit_history_history_id",
                        column: x => x.history_id,
                        principalTable: "history",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_person_for_unit_legal_unit_legal_unit_id",
                        column: x => x.legal_unit_id,
                        principalTable: "legal_unit",
                        principalColumn: "reg_id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_person_for_unit_local_unit_local_unit_id",
                        column: x => x.local_unit_id,
                        principalTable: "local_unit",
                        principalColumn: "reg_id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_person_for_unit_person_person_id",
                        column: x => x.person_id,
                        principalTable: "person",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_person_for_unit_person_type_person_type_id",
                        column: x => x.person_type_id,
                        principalTable: "person_type",
                        principalColumn: "id");
                });

            migrationBuilder.CreateIndex(
                name: "ix_activity_activity_category_id",
                table: "activity",
                column: "activity_category_id");

            migrationBuilder.CreateIndex(
                name: "ix_activity_updated_by",
                table: "activity",
                column: "updated_by");

            migrationBuilder.CreateIndex(
                name: "ix_activity_category_code",
                table: "activity_category",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_activity_category_parent_id",
                table: "activity_category",
                column: "parent_id");

            migrationBuilder.CreateIndex(
                name: "ix_activity_category_user_activity_category_id",
                table: "activity_category_user",
                column: "activity_category_id");

            migrationBuilder.CreateIndex(
                name: "ix_activity_legal_unit_activity_id",
                table: "activity_legal_unit",
                column: "activity_id");

            migrationBuilder.CreateIndex(
                name: "ix_activity_legal_unit_enterprise_unit_reg_id",
                table: "activity_legal_unit",
                column: "enterprise_unit_reg_id");

            migrationBuilder.CreateIndex(
                name: "ix_activity_legal_unit_history_id",
                table: "activity_legal_unit",
                column: "history_id");

            migrationBuilder.CreateIndex(
                name: "ix_activity_legal_unit_local_unit_reg_id",
                table: "activity_legal_unit",
                column: "local_unit_reg_id");

            migrationBuilder.CreateIndex(
                name: "ix_activity_legal_unit_unit_id",
                table: "activity_legal_unit",
                column: "unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_address_address_part1_address_part2_address_part3_region_id",
                table: "address",
                columns: new[] { "address_part1", "address_part2", "address_part3", "region_id", "latitude", "longitude" });

            migrationBuilder.CreateIndex(
                name: "ix_address_region_id",
                table: "address",
                column: "region_id");

            migrationBuilder.CreateIndex(
                name: "ix_analysis_log_analysis_queue_id_analyzed_unit_id",
                table: "analysis_log",
                columns: new[] { "analysis_queue_id", "analyzed_unit_id" });

            migrationBuilder.CreateIndex(
                name: "ix_analysis_queue_user_id",
                table: "analysis_queue",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_role_claims_role_id",
                table: "AspNetRoleClaims",
                column: "role_id");

            migrationBuilder.CreateIndex(
                name: "RoleNameIndex",
                table: "AspNetRoles",
                column: "normalized_name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_user_claims_user_id",
                table: "AspNetUserClaims",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_user_logins_user_id",
                table: "AspNetUserLogins",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_user_roles_role_id",
                table: "AspNetUserRoles",
                column: "role_id");

            migrationBuilder.CreateIndex(
                name: "EmailIndex",
                table: "AspNetUsers",
                column: "normalized_email");

            migrationBuilder.CreateIndex(
                name: "UserNameIndex",
                table: "AspNetUsers",
                column: "normalized_user_name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_country_code",
                table: "country",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_country_for_unit_country_id",
                table: "country_for_unit",
                column: "country_id");

            migrationBuilder.CreateIndex(
                name: "ix_country_for_unit_enterprise_group_id",
                table: "country_for_unit",
                column: "enterprise_group_id");

            migrationBuilder.CreateIndex(
                name: "ix_country_for_unit_legal_unit_id",
                table: "country_for_unit",
                column: "legal_unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_country_for_unit_local_unit_id",
                table: "country_for_unit",
                column: "local_unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_data_source_name",
                table: "data_source",
                column: "name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_data_source_user_id",
                table: "data_source",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_data_source_classification_code",
                table: "data_source_classification",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_data_source_queue_data_source_id",
                table: "data_source_queue",
                column: "data_source_id");

            migrationBuilder.CreateIndex(
                name: "ix_data_source_queue_user_id",
                table: "data_source_queue",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_data_uploading_log_data_source_queue_id",
                table: "data_uploading_log",
                column: "data_source_queue_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_actual_address_id",
                table: "enterprise_group",
                column: "actual_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_address_id",
                table: "enterprise_group",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_data_source_classification_id",
                table: "enterprise_group",
                column: "data_source_classification_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_ent_group_type_id",
                table: "enterprise_group",
                column: "ent_group_type_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_foreign_participation_id",
                table: "enterprise_group",
                column: "foreign_participation_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_name",
                table: "enterprise_group",
                column: "name");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_postal_address_id",
                table: "enterprise_group",
                column: "postal_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_registration_reason_id",
                table: "enterprise_group",
                column: "registration_reason_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_reorg_type_id",
                table: "enterprise_group",
                column: "reorg_type_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_size_id",
                table: "enterprise_group",
                column: "size_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_start_period",
                table: "enterprise_group",
                column: "start_period");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_unit_status_id",
                table: "enterprise_group",
                column: "unit_status_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_role_code",
                table: "enterprise_group_role",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_group_type_code",
                table: "enterprise_group_type",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_actual_address_id",
                table: "enterprise_unit",
                column: "actual_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_address_id",
                table: "enterprise_unit",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_data_source_classification_id",
                table: "enterprise_unit",
                column: "data_source_classification_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_ent_group_role_id",
                table: "enterprise_unit",
                column: "ent_group_role_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_enterprise_group_id",
                table: "enterprise_unit",
                column: "enterprise_group_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_foreign_participation_id",
                table: "enterprise_unit",
                column: "foreign_participation_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_inst_sector_code_id",
                table: "enterprise_unit",
                column: "inst_sector_code_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_legal_form_id",
                table: "enterprise_unit",
                column: "legal_form_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_name",
                table: "enterprise_unit",
                column: "name");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_postal_address_id",
                table: "enterprise_unit",
                column: "postal_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_registration_reason_id",
                table: "enterprise_unit",
                column: "registration_reason_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_reorg_type_id",
                table: "enterprise_unit",
                column: "reorg_type_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_short_name_reg_id_stat_id_tax_reg_id",
                table: "enterprise_unit",
                columns: new[] { "short_name", "reg_id", "stat_id", "tax_reg_id" });

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_size_id",
                table: "enterprise_unit",
                column: "size_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_start_period",
                table: "enterprise_unit",
                column: "start_period");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_stat_id",
                table: "enterprise_unit",
                column: "stat_id");

            migrationBuilder.CreateIndex(
                name: "ix_enterprise_unit_unit_status_id",
                table: "enterprise_unit",
                column: "unit_status_id");

            migrationBuilder.CreateIndex(
                name: "ix_foreign_participation_code",
                table: "foreign_participation",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_history_address_id",
                table: "history",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_history_name",
                table: "history",
                column: "name");

            migrationBuilder.CreateIndex(
                name: "ix_legal_form_code",
                table: "legal_form",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_actual_address_id",
                table: "legal_unit",
                column: "actual_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_address_id",
                table: "legal_unit",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_data_source_classification_id",
                table: "legal_unit",
                column: "data_source_classification_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_enterprise_unit_reg_id",
                table: "legal_unit",
                column: "enterprise_unit_reg_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_foreign_participation_id",
                table: "legal_unit",
                column: "foreign_participation_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_inst_sector_code_id",
                table: "legal_unit",
                column: "inst_sector_code_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_legal_form_id",
                table: "legal_unit",
                column: "legal_form_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_name",
                table: "legal_unit",
                column: "name");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_postal_address_id",
                table: "legal_unit",
                column: "postal_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_registration_reason_id",
                table: "legal_unit",
                column: "registration_reason_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_reorg_type_id",
                table: "legal_unit",
                column: "reorg_type_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_short_name_reg_id_stat_id_tax_reg_id",
                table: "legal_unit",
                columns: new[] { "short_name", "reg_id", "stat_id", "tax_reg_id" });

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_size_id",
                table: "legal_unit",
                column: "size_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_start_period",
                table: "legal_unit",
                column: "start_period");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_stat_id",
                table: "legal_unit",
                column: "stat_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_unit_unit_status_id",
                table: "legal_unit",
                column: "unit_status_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_actual_address_id",
                table: "local_unit",
                column: "actual_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_address_id",
                table: "local_unit",
                column: "address_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_data_source_classification_id",
                table: "local_unit",
                column: "data_source_classification_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_foreign_participation_id",
                table: "local_unit",
                column: "foreign_participation_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_inst_sector_code_id",
                table: "local_unit",
                column: "inst_sector_code_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_legal_form_id",
                table: "local_unit",
                column: "legal_form_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_legal_unit_id",
                table: "local_unit",
                column: "legal_unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_name",
                table: "local_unit",
                column: "name");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_postal_address_id",
                table: "local_unit",
                column: "postal_address_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_registration_reason_id",
                table: "local_unit",
                column: "registration_reason_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_reorg_type_id",
                table: "local_unit",
                column: "reorg_type_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_short_name_reg_id_stat_id_tax_reg_id",
                table: "local_unit",
                columns: new[] { "short_name", "reg_id", "stat_id", "tax_reg_id" });

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_size_id",
                table: "local_unit",
                column: "size_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_start_period",
                table: "local_unit",
                column: "start_period");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_stat_id",
                table: "local_unit",
                column: "stat_id");

            migrationBuilder.CreateIndex(
                name: "ix_local_unit_unit_status_id",
                table: "local_unit",
                column: "unit_status_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_country_id",
                table: "person",
                column: "country_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_given_name_surname",
                table: "person",
                columns: new[] { "given_name", "surname" });

            migrationBuilder.CreateIndex(
                name: "ix_person_for_unit_enterprise_group_id",
                table: "person_for_unit",
                column: "enterprise_group_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_for_unit_enterprise_unit_id",
                table: "person_for_unit",
                column: "enterprise_unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_for_unit_history_id",
                table: "person_for_unit",
                column: "history_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_for_unit_legal_unit_id",
                table: "person_for_unit",
                column: "legal_unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_for_unit_local_unit_id",
                table: "person_for_unit",
                column: "local_unit_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_for_unit_person_id",
                table: "person_for_unit",
                column: "person_id");

            migrationBuilder.CreateIndex(
                name: "ix_person_for_unit_person_type_id_local_unit_id_legal_unit_id_",
                table: "person_for_unit",
                columns: new[] { "person_type_id", "local_unit_id", "legal_unit_id", "enterprise_unit_id", "person_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_region_code",
                table: "region",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_region_parent_id",
                table: "region",
                column: "parent_id");

            migrationBuilder.CreateIndex(
                name: "ix_registration_reason_code",
                table: "registration_reason",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_reorg_type_code",
                table: "reorg_type",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sample_frame_user_id",
                table: "sample_frame",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_sector_code_code",
                table: "sector_code",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sector_code_parent_id",
                table: "sector_code",
                column: "parent_id");

            migrationBuilder.CreateIndex(
                name: "ix_unit_size_code",
                table: "unit_size",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_unit_status_code",
                table: "unit_status",
                column: "code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_user_region_region_id",
                table: "user_region",
                column: "region_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "activity_category_user");

            migrationBuilder.DropTable(
                name: "activity_legal_unit");

            migrationBuilder.DropTable(
                name: "analysis_log");

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
                name: "country_for_unit");

            migrationBuilder.DropTable(
                name: "custom_analysis_check");

            migrationBuilder.DropTable(
                name: "data_uploading_log");

            migrationBuilder.DropTable(
                name: "dictionary_version");

            migrationBuilder.DropTable(
                name: "person_for_unit");

            migrationBuilder.DropTable(
                name: "postal_index");

            migrationBuilder.DropTable(
                name: "report_tree");

            migrationBuilder.DropTable(
                name: "sample_frame");

            migrationBuilder.DropTable(
                name: "user_region");

            migrationBuilder.DropTable(
                name: "activity");

            migrationBuilder.DropTable(
                name: "analysis_queue");

            migrationBuilder.DropTable(
                name: "AspNetRoles");

            migrationBuilder.DropTable(
                name: "data_source_queue");

            migrationBuilder.DropTable(
                name: "history");

            migrationBuilder.DropTable(
                name: "local_unit");

            migrationBuilder.DropTable(
                name: "person");

            migrationBuilder.DropTable(
                name: "person_type");

            migrationBuilder.DropTable(
                name: "activity_category");

            migrationBuilder.DropTable(
                name: "data_source");

            migrationBuilder.DropTable(
                name: "legal_unit");

            migrationBuilder.DropTable(
                name: "country");

            migrationBuilder.DropTable(
                name: "AspNetUsers");

            migrationBuilder.DropTable(
                name: "enterprise_unit");

            migrationBuilder.DropTable(
                name: "enterprise_group");

            migrationBuilder.DropTable(
                name: "enterprise_group_role");

            migrationBuilder.DropTable(
                name: "legal_form");

            migrationBuilder.DropTable(
                name: "sector_code");

            migrationBuilder.DropTable(
                name: "address");

            migrationBuilder.DropTable(
                name: "data_source_classification");

            migrationBuilder.DropTable(
                name: "enterprise_group_type");

            migrationBuilder.DropTable(
                name: "foreign_participation");

            migrationBuilder.DropTable(
                name: "registration_reason");

            migrationBuilder.DropTable(
                name: "reorg_type");

            migrationBuilder.DropTable(
                name: "unit_size");

            migrationBuilder.DropTable(
                name: "unit_status");

            migrationBuilder.DropTable(
                name: "region");
        }
    }
}
