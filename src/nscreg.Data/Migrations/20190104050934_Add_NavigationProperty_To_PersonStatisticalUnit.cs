using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class Add_NavigationProperty_To_PersonStatisticalUnit : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnits_PersonType_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropColumn(
                name: "PersonType",
                table: "PersonStatisticalUnits");

            migrationBuilder.AddColumn<int>(
                name: "PersonTypeId",
                table: "PersonStatisticalUnits",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_PersonTypeId_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits",
                columns: new[] { "PersonTypeId", "Unit_Id", "Person_Id" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_PersonStatisticalUnits_PersonTypes_PersonTypeId",
                table: "PersonStatisticalUnits",
                column: "PersonTypeId",
                principalTable: "PersonTypes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_PersonStatisticalUnits_PersonTypes_PersonTypeId",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnits_PersonTypeId_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropColumn(
                name: "PersonTypeId",
                table: "PersonStatisticalUnits");

            migrationBuilder.AddColumn<int>(
                name: "PersonType",
                table: "PersonStatisticalUnits",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_PersonType_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits",
                columns: new[] { "PersonType", "Unit_Id", "Person_Id" },
                unique: true);
        }
    }
}
