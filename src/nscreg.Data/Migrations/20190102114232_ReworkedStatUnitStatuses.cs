using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class ReworkedStatUnitStatuses : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"Update StatisticalUnits Set UnitStatusId = Status Where UnitStatusId != Status AND Status != 1");

            migrationBuilder.DropPrimaryKey(
                name: "PK_UnitStatuses",
                table: "UnitStatuses");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "StatisticalUnits");

            migrationBuilder.RenameTable(
                name: "UnitStatuses",
                newName: "Statuses");

            migrationBuilder.AddPrimaryKey(
                name: "PK_Statuses",
                table: "Statuses",
                column: "Id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_Statuses",
                table: "Statuses");

            migrationBuilder.RenameTable(
                name: "Statuses",
                newName: "UnitStatuses");

            migrationBuilder.AddColumn<int>(
                name: "Status",
                table: "StatisticalUnits",
                nullable: false,
                defaultValue: 1);

            migrationBuilder.AddPrimaryKey(
                name: "PK_UnitStatuses",
                table: "UnitStatuses",
                column: "Id");
        }
    }
}
