using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class Change_Classified_From_String_To_Nullable_Bool : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<bool>(
                name: "Classified",
                table: "StatisticalUnits",
                nullable: true,
                oldClrType: typeof(string),
                oldNullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "Classified",
                table: "StatisticalUnits",
                nullable: true,
                oldClrType: typeof(bool),
                oldNullable: true);
        }
    }
}
