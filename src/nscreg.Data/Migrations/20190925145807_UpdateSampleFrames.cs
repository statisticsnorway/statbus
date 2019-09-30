using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class UpdateSampleFrames : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "FileName",
                table: "SampleFrames",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "FilePath",
                table: "SampleFrames",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "Status",
                table: "SampleFrames",
                nullable: false,
                defaultValue: 0);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "FileName",
                table: "SampleFrames");

            migrationBuilder.DropColumn(
                name: "FilePath",
                table: "SampleFrames");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "SampleFrames");
        }
    }
}
