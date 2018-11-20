using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class LanguageFieldsAddedToLookups : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "UnitStatuses",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "UnitStatuses",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "UnitsSize",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "UnitsSize",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "SectorCodes",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "SectorCodes",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "ReorgTypes",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "ReorgTypes",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "RegistrationReasons",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "RegistrationReasons",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "FullPathLanguage1",
                table: "Regions",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "FullPathLanguage2",
                table: "Regions",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "Regions",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "Regions",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "PostalIndices",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "PostalIndices",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "LegalForms",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "LegalForms",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "ForeignParticipations",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "ForeignParticipations",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "DataSourceClassifications",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "DataSourceClassifications",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "Countries",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "Countries",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage1",
                table: "ActivityCategories",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "NameLanguage2",
                table: "ActivityCategories",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "UnitStatuses");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "UnitStatuses");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "UnitsSize");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "UnitsSize");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "SectorCodes");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "SectorCodes");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "ReorgTypes");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "ReorgTypes");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "RegistrationReasons");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "RegistrationReasons");

            migrationBuilder.DropColumn(
                name: "FullPathLanguage1",
                table: "Regions");

            migrationBuilder.DropColumn(
                name: "FullPathLanguage2",
                table: "Regions");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "Regions");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "Regions");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "PostalIndices");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "PostalIndices");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "LegalForms");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "LegalForms");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "ForeignParticipations");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "ForeignParticipations");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "DataSourceClassifications");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "DataSourceClassifications");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "Countries");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "Countries");

            migrationBuilder.DropColumn(
                name: "NameLanguage1",
                table: "ActivityCategories");

            migrationBuilder.DropColumn(
                name: "NameLanguage2",
                table: "ActivityCategories");
        }
    }
}
