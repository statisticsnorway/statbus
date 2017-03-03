using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Metadata;

namespace nscreg.Data.Migrations
{
    public partial class EntGroupLegalUnitLink : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "StatisticalUnitReportingView");

            migrationBuilder.DropTable(
                name: "ReportingViews");

            migrationBuilder.AddColumn<int>(
                name: "EnterpriseGroupRegId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_EnterpriseGroupRegId",
                table: "StatisticalUnits",
                column: "EnterpriseGroupRegId");

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_EnterpriseGroups_EnterpriseGroupRegId",
                table: "StatisticalUnits",
                column: "EnterpriseGroupRegId",
                principalTable: "EnterpriseGroups",
                principalColumn: "RegId",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_EnterpriseGroups_EnterpriseGroupRegId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_EnterpriseGroupRegId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "EnterpriseGroupRegId",
                table: "StatisticalUnits");

            migrationBuilder.CreateTable(
                name: "ReportingViews",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    Name = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReportingViews", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "StatisticalUnitReportingView",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn),
                    RepViewId = table.Column<int>(nullable: false),
                    StatId = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StatisticalUnitReportingView", x => x.Id);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitReportingView_ReportingViews_RepViewId",
                        column: x => x.RepViewId,
                        principalTable: "ReportingViews",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_StatisticalUnitReportingView_StatisticalUnits_StatId",
                        column: x => x.StatId,
                        principalTable: "StatisticalUnits",
                        principalColumn: "RegId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitReportingView_RepViewId",
                table: "StatisticalUnitReportingView",
                column: "RepViewId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitReportingView_StatId",
                table: "StatisticalUnitReportingView",
                column: "StatId");
        }
    }
}
