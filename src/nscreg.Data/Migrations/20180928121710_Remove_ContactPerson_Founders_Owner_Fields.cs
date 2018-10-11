using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class Remove_ContactPerson_Founders_Owner_Fields : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ContactPerson",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "Founders",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "Owner",
                table: "StatisticalUnits");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ContactPerson",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Founders",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Owner",
                table: "StatisticalUnits",
                nullable: true);
        }
    }
}
