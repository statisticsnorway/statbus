using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class updateHistoryEnterpriseGroup : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EntGroupType",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropColumn(
                name: "LegalFormId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.RenameColumn(
                name: "RegMainActivityId",
                table: "EnterpriseGroupsHistory",
                newName: "EntGroupTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_EntGroupTypeId",
                table: "EnterpriseGroupsHistory",
                column: "EntGroupTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_ReorgTypeId",
                table: "EnterpriseGroupsHistory",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_UnitStatusId",
                table: "EnterpriseGroupsHistory",
                column: "UnitStatusId");

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroupsHistory_EnterpriseGroupTypes_EntGroupTypeId",
                table: "EnterpriseGroupsHistory",
                column: "EntGroupTypeId",
                principalTable: "EnterpriseGroupTypes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroupsHistory_SectorCodes_EntGroupTypeId",
                table: "EnterpriseGroupsHistory",
                column: "EntGroupTypeId",
                principalTable: "SectorCodes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroupsHistory_ReorgTypes_ReorgTypeId",
                table: "EnterpriseGroupsHistory",
                column: "ReorgTypeId",
                principalTable: "ReorgTypes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroupsHistory_Statuses_UnitStatusId",
                table: "EnterpriseGroupsHistory",
                column: "UnitStatusId",
                principalTable: "Statuses",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroupsHistory_EnterpriseGroupTypes_EntGroupTypeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroupsHistory_SectorCodes_EntGroupTypeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroupsHistory_ReorgTypes_ReorgTypeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroupsHistory_Statuses_UnitStatusId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroupsHistory_EntGroupTypeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroupsHistory_ReorgTypeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroupsHistory_UnitStatusId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.RenameColumn(
                name: "EntGroupTypeId",
                table: "EnterpriseGroupsHistory",
                newName: "RegMainActivityId");

            migrationBuilder.AddColumn<string>(
                name: "EntGroupType",
                table: "EnterpriseGroupsHistory",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "LegalFormId",
                table: "EnterpriseGroupsHistory",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Status",
                table: "EnterpriseGroupsHistory",
                nullable: true);

        }
    }
}
