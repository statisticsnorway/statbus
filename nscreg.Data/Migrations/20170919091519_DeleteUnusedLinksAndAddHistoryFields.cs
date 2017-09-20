using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class DeleteUnusedLinks : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_EnterpriseGroups_EnterpriseGroupRegId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_EnterpriseGroupRegId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "EnterpriseGroupRegId",
                table: "StatisticalUnits");

            migrationBuilder.AddColumn<string>(
                name: "HistoryLegalUnitIds",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "HistoryLocalUnitIds",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "HistoryEnterpriseUnitIds",
                table: "EnterpriseGroups",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "HistoryLegalUnitIds",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "HistoryLocalUnitIds",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "HistoryEnterpriseUnitIds",
                table: "EnterpriseGroups");

            migrationBuilder.AddColumn<int>(
                name: "EnterpriseGroupRegId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EnterpriseGroupRegId",
                table: "StatisticalUnits",
                column: "EnterpriseGroupRegId");

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_EnterpriseGroups_EnterpriseGroupRegId",
                table: "StatisticalUnits",
                column: "EnterpriseGroupRegId",
                principalTable: "EnterpriseGroups",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
