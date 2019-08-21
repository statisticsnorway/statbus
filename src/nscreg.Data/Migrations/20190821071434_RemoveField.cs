using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class RemoveField : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_StatisticalUnits_StatisticalUnitRegId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_StatisticalUnitRegId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "StatisticalUnitRegId",
                table: "StatisticalUnits");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "StatisticalUnitRegId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_StatisticalUnitRegId",
                table: "StatisticalUnits",
                column: "StatisticalUnitRegId");

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_StatisticalUnits_StatisticalUnitRegId",
                table: "StatisticalUnits",
                column: "StatisticalUnitRegId",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
