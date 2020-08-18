using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class UnitSizeCodeFieldAdd : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "Code",
                table: "UnitsSize",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.Sql(@"UPDATE UnitsSize SET Code = Id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Code",
                table: "UnitsSize");
        }
    }
}
