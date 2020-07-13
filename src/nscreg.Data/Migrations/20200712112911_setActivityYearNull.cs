using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class setActivityYearNull : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<int>(
                name: "Activity_Year",
                table: "Activities",
                nullable: true,
                oldClrType: typeof(int));
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<int>(
                name: "Activity_Year",
                table: "Activities",
                nullable: false,
                oldClrType: typeof(int),
                oldNullable: true);
        }
    }
}
