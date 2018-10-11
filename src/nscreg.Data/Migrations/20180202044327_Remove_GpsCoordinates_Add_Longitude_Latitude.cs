using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class Remove_GpsCoordinates_Add_Longitude_Latitude : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_GPS_coordinates",
                table: "Address");

            migrationBuilder.DropColumn(
                name: "GPS_coordinates",
                table: "Address");

            migrationBuilder.AddColumn<double>(
                name: "Latitude",
                table: "Address",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "Longitude",
                table: "Address",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_Latitude_Longitude",
                table: "Address",
                columns: new[]
                    {"Address_part1", "Address_part2", "Address_part3", "Region_id", "Latitude", "Longitude"});
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_Latitude_Longitude",
                table: "Address");

            migrationBuilder.DropColumn(
                name: "Latitude",
                table: "Address");

            migrationBuilder.DropColumn(
                name: "Longitude",
                table: "Address");

            migrationBuilder.AddColumn<string>(
                name: "GPS_coordinates",
                table: "Address",
                nullable: true);


            migrationBuilder.CreateIndex(
                name: "IX_Address_Address_part1_Address_part2_Address_part3_Region_id_GPS_coordinates",
                table: "Address",
                columns: new[] {"Address_part1", "Address_part2", "Address_part3", "Region_id", "GPS_coordinates"},
                unique: true);
        }
    }
}
