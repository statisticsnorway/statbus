using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Metadata;

namespace nscreg.Data.Migrations
{
    public partial class PersonStatUnitsIdentity : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_PersonStatisticalUnits_StatisticalUnits_Unit_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnits_GroupUnit_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropColumn(
                name: "Unit_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.AddColumn<int>(
                name: "Id",
                table: "PersonStatisticalUnits",
                nullable: false,
                defaultValue: 0)
                .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn);

            migrationBuilder.AddPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits",
                column: "Id");

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_GroupUnit_Id_Person_Id_StatUnit_Id",
                table: "PersonStatisticalUnits",
                columns: new[] { "GroupUnit_Id", "Person_Id", "StatUnit_Id" },
                unique: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnits_GroupUnit_Id_Person_Id_StatUnit_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropColumn(
                name: "Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.AddColumn<int>(
                name: "Unit_Id",
                table: "PersonStatisticalUnits",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddPrimaryKey(
                name: "PK_PersonStatisticalUnits",
                table: "PersonStatisticalUnits",
                columns: new[] { "Unit_Id", "Person_Id", "PersonType" });

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_GroupUnit_Id",
                table: "PersonStatisticalUnits",
                column: "GroupUnit_Id");

            migrationBuilder.AddForeignKey(
                name: "FK_PersonStatisticalUnits_StatisticalUnits_Unit_Id",
                table: "PersonStatisticalUnits",
                column: "Unit_Id",
                principalTable: "StatisticalUnits",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
