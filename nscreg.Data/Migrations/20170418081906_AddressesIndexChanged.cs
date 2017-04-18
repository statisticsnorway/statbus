using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddressesIndexChanged : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Address_Geographical_codes_AddressDetails",
                table: "Address");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Geographical_codes_AddressDetails_GPS_coordinates",
                table: "Address",
                columns: new[] { "Geographical_codes", "AddressDetails", "GPS_coordinates" },
                unique: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Address_Geographical_codes_AddressDetails_GPS_coordinates",
                table: "Address");

            migrationBuilder.CreateIndex(
                name: "IX_Address_Geographical_codes_AddressDetails",
                table: "Address",
                columns: new[] { "Geographical_codes", "AddressDetails" },
                unique: true);
        }
    }
}
