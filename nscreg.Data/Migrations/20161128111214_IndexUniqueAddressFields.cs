using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class IndexUniqueAddressFields : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<int>(
                name: "AddressId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_AddressId",
                table: "EnterpriseGroups",
                column: "AddressId");

            migrationBuilder.CreateIndex(
                name: "IX_Unique_AddressFields",
                table: "Address",
                columns: new[] { "Address_part1", "Address_part2", "Address_part3", "Address_part4", "Address_part5" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_Address_AddressId",
                table: "EnterpriseGroups",
                column: "AddressId",
                principalTable: "Address",
                principalColumn: "Address_id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_Address_AddressId",
                table: "EnterpriseGroups");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_AddressId",
                table: "EnterpriseGroups");

            migrationBuilder.DropIndex(
                name: "IX_Unique_AddressFields",
                table: "Address");

            migrationBuilder.AlterColumn<int>(
                name: "AddressId",
                table: "EnterpriseGroups",
                nullable: false);
        }
    }
}
