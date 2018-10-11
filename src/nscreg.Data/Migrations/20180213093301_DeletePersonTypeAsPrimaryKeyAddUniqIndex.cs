using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class DeletePersonTypeAsPrimaryKeyAddUniqIndex : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits");

            migrationBuilder.AddPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits",
                columns: new[] { "Unit_Id", "Person_Id" });

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_PersonType_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits",
                columns: new[] { "PersonType", "Unit_Id", "Person_Id" },
                unique: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnits_PersonType_Unit_Id_Person_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.AddPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits",
                columns: new[] { "Unit_Id", "Person_Id", "PersonType" });
        }
    }
}
