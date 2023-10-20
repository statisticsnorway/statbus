using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace nscreg.Data.Migrations
{
    /// <inheritdoc />
    public partial class DropColumnAddressIdFromStatisticalUnitsTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_Address_AddressId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_AddressId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "AddressId",
                table: "StatisticalUnits");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AddressId",
                table: "StatisticalUnits",
                type: "integer",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_AddressId",
                table: "StatisticalUnits",
                column: "AddressId");

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_Address_AddressId",
                table: "StatisticalUnits",
                column: "AddressId",
                principalTable: "Address",
                principalColumn: "Address_id");
        }
    }
}
