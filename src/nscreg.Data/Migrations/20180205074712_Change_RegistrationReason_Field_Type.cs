using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Metadata;

namespace nscreg.Data.Migrations
{
    public partial class Change_RegistrationReason_Field_Type : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RegistrationReason",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "RegistrationReason",
                table: "EnterpriseGroups");

            migrationBuilder.AddColumn<int>(
                name: "RegistrationReasonId",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "RegistrationReasonId",
                table: "EnterpriseGroups",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "RegistrationReasons",
                columns: table => new
                {
                    Id = table.Column<int>(nullable: false)
                        .Annotation("SqlServer:ValueGenerationStrategy", SqlServerValueGenerationStrategy.IdentityColumn),
                    Code = table.Column<string>(nullable: true),
                    IsDeleted = table.Column<bool>(nullable: false, defaultValue: false),
                    Name = table.Column<string>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RegistrationReasons", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_RegistrationReasonId",
                table: "StatisticalUnits",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_RegistrationReasonId",
                table: "EnterpriseGroups",
                column: "RegistrationReasonId");

            migrationBuilder.CreateIndex(
                name: "IX_RegistrationReasons_Code",
                table: "RegistrationReasons",
                column: "Code",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_RegistrationReasons_RegistrationReasonId",
                table: "EnterpriseGroups",
                column: "RegistrationReasonId",
                principalTable: "RegistrationReasons",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_RegistrationReasons_RegistrationReasonId",
                table: "StatisticalUnits",
                column: "RegistrationReasonId",
                principalTable: "RegistrationReasons",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_RegistrationReasons_RegistrationReasonId",
                table: "EnterpriseGroups");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_RegistrationReasons_RegistrationReasonId",
                table: "StatisticalUnits");

            migrationBuilder.DropTable(
                name: "RegistrationReasons");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_RegistrationReasonId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_RegistrationReasonId",
                table: "EnterpriseGroups");

            migrationBuilder.DropColumn(
                name: "RegistrationReasonId",
                table: "StatisticalUnits");

            migrationBuilder.DropColumn(
                name: "RegistrationReasonId",
                table: "EnterpriseGroups");

            migrationBuilder.AddColumn<string>(
                name: "RegistrationReason",
                table: "StatisticalUnits",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RegistrationReason",
                table: "EnterpriseGroups",
                nullable: true);
        }
    }
}
