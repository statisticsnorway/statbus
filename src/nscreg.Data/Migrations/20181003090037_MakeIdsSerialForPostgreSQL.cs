using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Metadata;

namespace nscreg.Data.Migrations
{
    public partial class MakeIdsSerialForPostgreSQL : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            if (migrationBuilder.ActiveProvider == "Npgsql.EntityFrameworkCore.PostgreSQL")
            {
                migrationBuilder.AlterColumn<int>(
                name: "Id",
                table: "UnitStatuses",
                nullable: false,
                oldClrType: typeof(int))
                .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "UnitsSize",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "RegId",
                    table: "StatisticalUnits",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "SectorCodes",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "SampleFrames",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "ReorgTypes",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "RegistrationReasons",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Regions",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "PostalIndices",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Persons",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "LegalForms",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "ForeignParticipations",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "RegId",
                    table: "EnterpriseGroups",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DictionaryVersions",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataUploadingLogs",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataSourceQueues",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataSourceClassifications",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataSources",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "CustomAnalysisChecks",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Countries",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AnalysisQueues",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AnalysisLogs",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Address_id",
                    table: "Address",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "ActivityCategories",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Activities",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AspNetUserClaims",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AspNetRoleClaims",
                    nullable: false,
                    oldClrType: typeof(int))
                    .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);
            }
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            if (migrationBuilder.ActiveProvider == "Npgsql.EntityFrameworkCore.PostgreSQL")
            {
                migrationBuilder.AlterColumn<int>(
                name: "Id",
                table: "UnitStatuses",
                nullable: false,
                oldClrType: typeof(int))
                .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "UnitsSize",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "RegId",
                    table: "StatisticalUnits",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "SectorCodes",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "SampleFrames",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "ReorgTypes",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "RegistrationReasons",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Regions",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "PostalIndices",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Persons",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "LegalForms",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "ForeignParticipations",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "RegId",
                    table: "EnterpriseGroups",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DictionaryVersions",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataUploadingLogs",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataSourceQueues",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataSourceClassifications",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "DataSources",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "CustomAnalysisChecks",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Countries",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AnalysisQueues",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AnalysisLogs",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Address_id",
                    table: "Address",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "ActivityCategories",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "Activities",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AspNetUserClaims",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);

                migrationBuilder.AlterColumn<int>(
                    name: "Id",
                    table: "AspNetRoleClaims",
                    nullable: false,
                    oldClrType: typeof(int))
                    .OldAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn);
            }
        }
    }
}
