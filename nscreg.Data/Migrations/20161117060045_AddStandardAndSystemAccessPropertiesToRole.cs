using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddStandardAndSystemAccessPropertiesToRole : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AccessToSystemFunctions",
                table: "AspNetRoles",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StandardDataAccess",
                table: "AspNetRoles",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AccessToSystemFunctions",
                table: "AspNetRoles");

            migrationBuilder.DropColumn(
                name: "StandardDataAccess",
                table: "AspNetRoles");
        }
    }
}
