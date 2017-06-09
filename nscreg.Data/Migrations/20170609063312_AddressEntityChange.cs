using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddressEntityChange : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Address_part4_Address_part5_Region_id_GPS_coordinates",
                table: "Address");

            migrationBuilder.DropColumn(
                name: "Address_part4",
                table: "Address");

            migrationBuilder.DropColumn(
                name: "Address_part5",
                table: "Address");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_GPS_coordinates",
                table: "Address",
                columns: new[] { "Address_part1", "Address_part2", "Address_part3", "Region_id", "GPS_coordinates" },
                unique: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_GPS_coordinates",
                table: "Address");

            migrationBuilder.AddColumn<string>(
                name: "Address_part4",
                table: "Address",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Address_part5",
                table: "Address",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Address_part4_Address_part5_Region_id_GPS_coordinates",
                table: "Address",
                columns: new[] { "Address_part1", "Address_part2", "Address_part3", "Address_part4", "Address_part5", "Region_id", "GPS_coordinates" },
                unique: true);
        }
    }
}
