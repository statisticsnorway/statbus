using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class UpdateEntGroupTypesAndRoles : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EntGroupRole",
                table: "StatisticalUnits");

            migrationBuilder.AddColumn<int>(
                name: "EntGroupRoleId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Code",
                table: "EnterpriseGroupTypes",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "EnterpriseGroupRoles",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Name = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true),
                    Code = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroupRoles", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EntGroupRoleId",
                table: "StatisticalUnits",
                column: "EntGroupRoleId");

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_EnterpriseGroupRoles_EntGroupRoleId",
                table: "StatisticalUnits",
                column: "EntGroupRoleId",
                principalTable: "EnterpriseGroupRoles",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.Sql("UPDATE EnterpriseGroupTypes SET Code = Id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_EnterpriseGroupRoles_EntGroupRoleId",
                table: "StatisticalUnits");

            migrationBuilder.DropTable(
                name: "EnterpriseGroupRoles");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_EntGroupRoleId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "EntGroupRoleId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "Code",
                table: "EnterpriseGroupTypes");

            migrationBuilder.AddColumn<string>(
                name: "EntGroupRole",
                table: "StatisticalUnits",
                nullable: true);
        }
    }
}
