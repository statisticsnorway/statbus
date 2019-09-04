using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class RemoveFieldStatisticalUnitRegId : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_StatisticalUnits_StatisticalUnitRegId",
                table: "EnterpriseGroups");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_StatisticalUnitRegId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "StatisticalUnitRegId",
                table: "EnterpriseGroups");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "StatisticalUnitRegId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_StatisticalUnitRegId",
                table: "EnterpriseGroups",
                column: "StatisticalUnitRegId");

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_StatisticalUnits_StatisticalUnitRegId",
                table: "EnterpriseGroups",
                column: "StatisticalUnitRegId",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
