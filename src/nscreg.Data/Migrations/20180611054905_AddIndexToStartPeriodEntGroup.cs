using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddIndexToStartPeriodEntGroup : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_StartPeriod",
                table: "EnterpriseGroups",
                column: "StartPeriod");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_StartPeriod",
                table: "EnterpriseGroups");
        }
    }
}
