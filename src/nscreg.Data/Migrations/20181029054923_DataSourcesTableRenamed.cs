using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class DataSourcesTableRenamed : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_DataSources_AspNetUsers_UserId",
                table: "DataSources");

            migrationBuilder.DropForeignKey(
                name: "FK_DataSourceQueues_DataSources_DataSourceId",
                table: "DataSourceQueues");

            migrationBuilder.DropPrimaryKey(
                name: "PK_DataSources",
                table: "DataSources");

            migrationBuilder.RenameTable(
                name: "DataSources",
                newName: "DataSourceUploads");

            migrationBuilder.RenameIndex(
                name: "IX_DataSources_UserId",
                table: "DataSourceUploads",
                newName: "IX_DataSourceUploads_UserId");

            migrationBuilder.RenameIndex(
                name: "IX_DataSources_Name",
                table: "DataSourceUploads",
                newName: "IX_DataSourceUploads_Name");

            migrationBuilder.AddPrimaryKey(
                name: "PK_DataSourceUploads",
                table: "DataSourceUploads",
                column: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_DataSourceUploads_AspNetUsers_UserId",
                table: "DataSourceUploads",
                column: "UserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_DataSourceQueues_DataSourceUploads_DataSourceId",
                table: "DataSourceQueues",
                column: "DataSourceId",
                principalTable: "DataSourceUploads",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_DataSourceUploads_AspNetUsers_UserId",
                table: "DataSourceUploads");

            migrationBuilder.DropForeignKey(
                name: "FK_DataSourceQueues_DataSourceUploads_DataSourceId",
                table: "DataSourceQueues");

            migrationBuilder.DropPrimaryKey(
                name: "PK_DataSourceUploads",
                table: "DataSourceUploads");

            migrationBuilder.RenameTable(
                name: "DataSourceUploads",
                newName: "DataSources");

            migrationBuilder.RenameIndex(
                name: "IX_DataSourceUploads_UserId",
                table: "DataSources",
                newName: "IX_DataSources_UserId");

            migrationBuilder.RenameIndex(
                name: "IX_DataSourceUploads_Name",
                table: "DataSources",
                newName: "IX_DataSources_Name");

            migrationBuilder.AddPrimaryKey(
                name: "PK_DataSources",
                table: "DataSources",
                column: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_DataSources_AspNetUsers_UserId",
                table: "DataSources",
                column: "UserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_DataSourceQueues_DataSources_DataSourceId",
                table: "DataSourceQueues",
                column: "DataSourceId",
                principalTable: "DataSources",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
