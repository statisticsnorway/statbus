using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class ParentIdDeleted : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_StatisticalUnits_ParentId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_ParentId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "ParentId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "ParentId",
                table: "EnterpriseGroups");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ParentId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ParentId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ParentId",
                table: "StatisticalUnits",
                column: "ParentId");

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_StatisticalUnits_ParentId",
                table: "StatisticalUnits",
                column: "ParentId",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
