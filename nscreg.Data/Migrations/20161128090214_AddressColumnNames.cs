using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddressColumnNames : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_Address_AddressId",
                table: "StatisticalUnits");

            migrationBuilder.AlterColumn<int>(
                name: "AddressId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Unique_GPS",
                table: "Address",
                column: "GpsCoordinates",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_Address_AddressId",
                table: "StatisticalUnits",
                column: "AddressId",
                principalTable: "Address",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.RenameColumn(
                name: "GpsCoordinates",
                table: "Address",
                newName: "GPS_coordinates");

            migrationBuilder.RenameColumn(
                name: "GeographicalCodes",
                table: "Address",
                newName: "Geographical_codes");

            migrationBuilder.RenameColumn(
                name: "AddressPart5",
                table: "Address",
                newName: "Address_part5");

            migrationBuilder.RenameColumn(
                name: "AddressPart4",
                table: "Address",
                newName: "Address_part4");

            migrationBuilder.RenameColumn(
                name: "AddressPart3",
                table: "Address",
                newName: "Address_part3");

            migrationBuilder.RenameColumn(
                name: "AddressPart2",
                table: "Address",
                newName: "Address_part2");

            migrationBuilder.RenameColumn(
                name: "AddressPart1",
                table: "Address",
                newName: "Address_part1");

            migrationBuilder.RenameColumn(
                name: "Id",
                table: "Address",
                newName: "Address_id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_Address_AddressId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_Unique_GPS",
                table: "Address");

            migrationBuilder.AlterColumn<int>(
                name: "AddressId",
                table: "StatisticalUnits",
                nullable: false);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_Address_AddressId",
                table: "StatisticalUnits",
                column: "AddressId",
                principalTable: "Address",
                principalColumn: "Address_id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.RenameColumn(
                name: "GPS_coordinates",
                table: "Address",
                newName: "GpsCoordinates");

            migrationBuilder.RenameColumn(
                name: "Geographical_codes",
                table: "Address",
                newName: "GeographicalCodes");

            migrationBuilder.RenameColumn(
                name: "Address_part5",
                table: "Address",
                newName: "AddressPart5");

            migrationBuilder.RenameColumn(
                name: "Address_part4",
                table: "Address",
                newName: "AddressPart4");

            migrationBuilder.RenameColumn(
                name: "Address_part3",
                table: "Address",
                newName: "AddressPart3");

            migrationBuilder.RenameColumn(
                name: "Address_part2",
                table: "Address",
                newName: "AddressPart2");

            migrationBuilder.RenameColumn(
                name: "Address_part1",
                table: "Address",
                newName: "AddressPart1");

            migrationBuilder.RenameColumn(
                name: "Address_id",
                table: "Address",
                newName: "Id");
        }
    }
}
