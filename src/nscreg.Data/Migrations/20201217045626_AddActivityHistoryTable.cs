using System;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddActivityHistoryTable : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DELETE FROM [ActivityStatisticalUnitHistory]", true);
            migrationBuilder.DropForeignKey(
                name: "FK_ActivityStatisticalUnitHistory_Activities_Activity_Id",
                table: "ActivityStatisticalUnitHistory");

            migrationBuilder.CreateTable(
                name: "ActivitiesHistory",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Id_Date = table.Column<DateTime>(nullable: false),
                    ActivityCategoryId = table.Column<int>(nullable: false),
                    Activity_Year = table.Column<int>(nullable: true),
                    Activity_Type = table.Column<int>(nullable: false),
                    Employees = table.Column<int>(nullable: true),
                    Turnover = table.Column<decimal>(nullable: true),
                    Updated_By = table.Column<string>(nullable: false),
                    Updated_Date = table.Column<DateTime>(nullable: false),
                    ParentId = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivitiesHistory", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ActivitiesHistory_ActivityCategories_ActivityCategoryId",
                        column: x => x.ActivityCategoryId,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivitiesHistory_AspNetUsers_Updated_By",
                        column: x => x.Updated_By,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ActivitiesHistory_ActivityCategoryId",
                table: "ActivitiesHistory",
                column: "ActivityCategoryId");

            migrationBuilder.CreateIndex(
                name: "IX_ActivitiesHistory_Updated_By",
                table: "ActivitiesHistory",
                column: "Updated_By");

            migrationBuilder.AddForeignKey(
                name: "FK_ActivityStatisticalUnitHistory_ActivitiesHistory_Activity_Id",
                table: "ActivityStatisticalUnitHistory",
                column: "Activity_Id",
                principalTable: "ActivitiesHistory",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DELETE FROM [ActivityStatisticalUnitHistory]", true);

            migrationBuilder.DropForeignKey(
                name: "FK_ActivityStatisticalUnitHistory_ActivitiesHistory_Activity_Id",
                table: "ActivityStatisticalUnitHistory");

            migrationBuilder.DropTable(
                name: "ActivitiesHistory");

            migrationBuilder.AddForeignKey(
                name: "FK_ActivityStatisticalUnitHistory_Activities_Activity_Id",
                table: "ActivityStatisticalUnitHistory",
                column: "Activity_Id",
                principalTable: "Activities",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
