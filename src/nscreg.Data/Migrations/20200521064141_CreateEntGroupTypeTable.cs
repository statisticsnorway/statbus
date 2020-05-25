using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class CreateEntGroupTypeTable : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EntGroupType",
                table: "EnterpriseGroups");

            migrationBuilder.AddColumn<int>(
                name: "EntGroupTypeId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "EnterpriseGroupTypes",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    IsDeleted = table.Column<bool>(nullable: false),
                    Name = table.Column<string>(nullable: true),
                    NameLanguage1 = table.Column<string>(nullable: true),
                    NameLanguage2 = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroupTypes", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_EntGroupTypeId",
                table: "EnterpriseGroups",
                column: "EntGroupTypeId");

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_EnterpriseGroupTypes_EntGroupTypeId",
                table: "EnterpriseGroups",
                column: "EntGroupTypeId",
                principalTable: "EnterpriseGroupTypes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_EnterpriseGroupTypes_EntGroupTypeId",
                table: "EnterpriseGroups");

            migrationBuilder.DropTable(
                name: "EnterpriseGroupTypes");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_EntGroupTypeId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "EntGroupTypeId",
                table: "EnterpriseGroups");

            migrationBuilder.AddColumn<string>(
                name: "EntGroupType",
                table: "EnterpriseGroups",
                nullable: true);
        }
    }
}
