using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class ChangeTypeRefNoColumnToNvarchar : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "RefNo",
                table: "StatisticalUnits",
                maxLength: 25,
                nullable: true,
                oldClrType: typeof(int),
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "RefNo",
                table: "StatisticalUnitHistory",
                maxLength: 25,
                nullable: true,
                oldClrType: typeof(int),
                oldNullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<int>(
                name: "RefNo",
                table: "StatisticalUnits",
                nullable: true,
                oldClrType: typeof(string),
                oldMaxLength: 25,
                oldNullable: true);

            migrationBuilder.AlterColumn<int>(
                name: "RefNo",
                table: "StatisticalUnitHistory",
                nullable: true,
                oldClrType: typeof(string),
                oldMaxLength: 25,
                oldNullable: true);
        }
    }
}
