using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class DeleteIntSectorCodeInGroupHistory : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroupsHistory_SectorCodes_EntGroupTypeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropColumn(
                name: "InstSectorCodeId",
                table: "EnterpriseGroupsHistory");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "InstSectorCodeId",
                table: "EnterpriseGroupsHistory",
                nullable: true);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroupsHistory_SectorCodes_EntGroupTypeId",
                table: "EnterpriseGroupsHistory",
                column: "EntGroupTypeId",
                principalTable: "SectorCodes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
