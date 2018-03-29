using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class DeleteParrentFieldFromEnterpriseGroup : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_EnterpriseGroups_ParrentRegId",
                table: "EnterpriseGroups");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_ParrentRegId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "ParrentRegId",
                table: "EnterpriseGroups");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ParrentRegId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_ParrentRegId",
                table: "EnterpriseGroups",
                column: "ParrentRegId");

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_EnterpriseGroups_ParrentRegId",
                table: "EnterpriseGroups",
                column: "ParrentRegId",
                principalTable: "EnterpriseGroups",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
