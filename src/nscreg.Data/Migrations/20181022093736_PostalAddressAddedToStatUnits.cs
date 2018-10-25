using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class PostalAddressAddedToStatUnits : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "PostalAddressId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PostalAddressId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_PostalAddressId",
                table: "StatisticalUnits",
                column: "PostalAddressId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_PostalAddressId",
                table: "EnterpriseGroups",
                column: "PostalAddressId");

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_Address_PostalAddressId",
                table: "EnterpriseGroups",
                column: "PostalAddressId",
                principalTable: "Address",
                principalColumn: "Address_id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_Address_PostalAddressId",
                table: "StatisticalUnits",
                column: "PostalAddressId",
                principalTable: "Address",
                principalColumn: "Address_id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_Address_PostalAddressId",
                table: "EnterpriseGroups");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_Address_PostalAddressId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_PostalAddressId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_PostalAddressId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "PostalAddressId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "PostalAddressId",
                table: "EnterpriseGroups");
        }
    }
}
