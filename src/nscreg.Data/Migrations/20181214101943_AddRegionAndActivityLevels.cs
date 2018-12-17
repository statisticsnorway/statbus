using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddRegionAndActivityLevels : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "RegionLevel",
                table: "Regions",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ActivityCategoryLevel",
                table: "ActivityCategories",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Regions_ParentId",
                table: "Regions",
                column: "ParentId");

            migrationBuilder.AddForeignKey(
                name: "FK_Regions_Regions_ParentId",
                table: "Regions",
                column: "ParentId",
                principalTable: "Regions",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Regions_Regions_ParentId",
                table: "Regions");

            migrationBuilder.DropIndex(
                name: "IX_Regions_ParentId",
                table: "Regions");

            migrationBuilder.DropColumn(
                name: "RegionLevel",
                table: "Regions");

            migrationBuilder.DropColumn(
                name: "ActivityCategoryLevel",
                table: "ActivityCategories");
        }
    }
}
