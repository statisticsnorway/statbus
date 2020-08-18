using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class RemoveFieldForeignParticipationCountryId : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_PersonStatisticalUnits_StatisticalUnits_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnitHistory_Countries_Id",
                table: "StatisticalUnitHistory");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_Countries_Id",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_CountryId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnitHistory_CountryId",
                table: "StatisticalUnitHistory");

            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnits_StatUnit_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnitHistory_StatUnit_Id",
                table: "PersonStatisticalUnitHistory");

            migrationBuilder.DropColumn(
                name: "ForeignParticipationCountryId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "ForeignParticipationCountryId",
                table: "StatisticalUnitHistory");

            migrationBuilder.DropColumn(
                name: "StatUnit_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropColumn(
                name: "StatUnit_Id",
                table: "PersonStatisticalUnitHistory");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ForeignParticipationCountryId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ForeignParticipationCountryId",
                table: "StatisticalUnitHistory",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "StatUnit_Id",
                table: "PersonStatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "StatUnit_Id",
                table: "PersonStatisticalUnitHistory",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_Id",
                table: "StatisticalUnits",
                column: "ForeignParticipationCountryId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_Id",
                table: "StatisticalUnitHistory",
                column: "ForeignParticipationCountryId");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_StatUnit_Id",
                table: "PersonStatisticalUnits",
                column: "StatUnit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnitHistory_StatUnit_Id",
                table: "PersonStatisticalUnitHistory",
                column: "StatUnit_Id");

            migrationBuilder.AddForeignKey(
                name: "FK_PersonStatisticalUnits_StatisticalUnits_Id",
                table: "PersonStatisticalUnits",
                column: "StatUnit_Id",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnitHistory_Countries_Id",
                table: "StatisticalUnitHistory",
                column: "ForeignParticipationCountryId",
                principalTable: "Countries",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_Countries_Id",
                table: "StatisticalUnits",
                column: "ForeignParticipationCountryId",
                principalTable: "Countries",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
