using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddIndexInDb : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_AnalysisLogs_AnalysisQueueId",
                table: "AnalysisLogs");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_StatId_EndPeriod",
                table: "StatisticalUnitHistory",
                columns: new[] { "StatId", "EndPeriod" });

            migrationBuilder.CreateIndex(
                name: "IX_PersonStatisticalUnits_Unit_Id",
                table: "PersonStatisticalUnits",
                column: "Unit_Id");

            migrationBuilder.CreateIndex(
                name: "IX_AnalysisLogs_AnalysisQueueId_AnalyzedUnitId",
                table: "AnalysisLogs",
                columns: new[] { "AnalysisQueueId", "AnalyzedUnitId" });

            migrationBuilder.CreateIndex(
                name: "IX_ActivityStatisticalUnits_Unit_Id",
                table: "ActivityStatisticalUnits",
                column: "Unit_Id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnitHistory_StatId_EndPeriod",
                table: "StatisticalUnitHistory");

            migrationBuilder.DropIndex(
                name: "IX_PersonStatisticalUnits_Unit_Id",
                table: "PersonStatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_AnalysisLogs_AnalysisQueueId_AnalyzedUnitId",
                table: "AnalysisLogs");

            migrationBuilder.DropIndex(
                name: "IX_ActivityStatisticalUnits_Unit_Id",
                table: "ActivityStatisticalUnits");

            migrationBuilder.CreateIndex(
                name: "IX_AnalysisLogs_AnalysisQueueId",
                table: "AnalysisLogs",
                column: "AnalysisQueueId");
        }
    }
}
