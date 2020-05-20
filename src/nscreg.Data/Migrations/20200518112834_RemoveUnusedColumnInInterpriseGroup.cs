using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class RemoveUnusedColumnInInterpriseGroup : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "InstSectorCodeId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "LegalFormId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "RegMainActivityId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "EnterpriseGroups");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "InstSectorCodeId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "LegalFormId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "RegMainActivityId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Status",
                table: "EnterpriseGroups",
                nullable: true);
        }
    }
}
