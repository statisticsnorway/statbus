using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class SampleFramesAddGeneratedTime : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "FileName",
                table: "SampleFrames");

            migrationBuilder.AddColumn<DateTime>(
                name: "GeneratedDateTime",
                table: "SampleFrames",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "GeneratedDateTime",
                table: "SampleFrames");

            migrationBuilder.AddColumn<string>(
                name: "FileName",
                table: "SampleFrames",
                nullable: true);
        }
    }
}
