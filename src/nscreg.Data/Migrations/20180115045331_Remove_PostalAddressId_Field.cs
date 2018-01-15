using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class Remove_PostalAddressId_Field : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PostalAddressId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "PostalAddressId",
                table: "EnterpriseGroups");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "PostalAddressId",
                table: "StatisticalUnits",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "PostalAddressId",
                table: "EnterpriseGroups",
                nullable: true);
        }
    }
}
