using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class DeletePersonTypeAsPrimaryKeyAddUniqIndex : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            if (migrationBuilder.ActiveProvider == "Pomelo.EntityFrameworkCore.MySql")
            {
                migrationBuilder.DropForeignKey(
                    name: "FK_PersonStatisticalUnits_Persons_Person_Id",
                    table: "PersonStatisticalUnits");

                migrationBuilder.DropForeignKey(
                    name: "FK_PersonStatisticalUnits_StatisticalUnits_Unit_Id",
                    table: "PersonStatisticalUnits");
            }

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

            if (migrationBuilder.ActiveProvider == "Pomelo.EntityFrameworkCore.MySql")
            {
                migrationBuilder.AddForeignKey(
                    name: "FK_PersonStatisticalUnits_Persons_Person_Id",
                    table: "PersonStatisticalUnits",
                    column: "Person_Id",
                    principalTable: "Persons",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);

                migrationBuilder.AddForeignKey(
                    name: "FK_PersonStatisticalUnits_StatisticalUnits_Unit_Id",
                    table: "PersonStatisticalUnits",
                    column: "Unit_Id",
                    principalTable: "StatisticalUnits",
                    principalColumn: "RegId",
                    onDelete: ReferentialAction.Restrict);
            }
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            if (migrationBuilder.ActiveProvider == "Pomelo.EntityFrameworkCore.MySql")
            {
                migrationBuilder.DropForeignKey(
                    name: "FK_PersonStatisticalUnits_Persons_Person_Id",
                    table: "PersonStatisticalUnits");

                migrationBuilder.DropForeignKey(
                    name: "FK_PersonStatisticalUnits_StatisticalUnits_Unit_Id",
                    table: "PersonStatisticalUnits");
            }

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

            if (migrationBuilder.ActiveProvider == "Pomelo.EntityFrameworkCore.MySql")
            {
                migrationBuilder.AddForeignKey(
                    name: "FK_PersonStatisticalUnits_Persons_Person_Id",
                    table: "PersonStatisticalUnits",
                    column: "Person_Id",
                    principalTable: "Persons",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);

                migrationBuilder.AddForeignKey(
                    name: "FK_PersonStatisticalUnits_StatisticalUnits_Unit_Id",
                    table: "PersonStatisticalUnits",
                    column: "Unit_Id",
                    principalTable: "StatisticalUnits",
                    principalColumn: "RegId",
                    onDelete: ReferentialAction.Restrict);
            }
        }
    }
}
