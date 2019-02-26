using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class ChangedFKsForReferences : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "Size",
                table: "StatisticalUnits",
                newName: "SizeId");

            migrationBuilder.RenameColumn(
                name: "Size",
                table: "StatisticalUnitHistory",
                newName: "SizeId");

            migrationBuilder.RenameColumn(
                name: "Size",
                table: "EnterpriseGroupsHistory",
                newName: "SizeId");

            migrationBuilder.RenameColumn(
                name: "Size",
                table: "EnterpriseGroups",
                newName: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_ReorgTypeId",
                table: "StatisticalUnits",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_SizeId",
                table: "StatisticalUnits",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnits_UnitStatusId",
                table: "StatisticalUnits",
                column: "UnitStatusId");

            migrationBuilder.CreateIndex(
                name: "IX_StatisticalUnitHistory_SizeId",
                table: "StatisticalUnitHistory",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroupsHistory_SizeId",
                table: "EnterpriseGroupsHistory",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_ReorgTypeId",
                table: "EnterpriseGroups",
                column: "ReorgTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_SizeId",
                table: "EnterpriseGroups",
                column: "SizeId");

            migrationBuilder.CreateIndex(
                name: "IX_EnterpriseGroups_UnitStatusId",
                table: "EnterpriseGroups",
                column: "UnitStatusId");

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_ReorgTypes_ReorgTypeId",
                table: "EnterpriseGroups",
                column: "ReorgTypeId",
                principalTable: "ReorgTypes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_UnitsSize_SizeId",
                table: "EnterpriseGroups",
                column: "SizeId",
                principalTable: "UnitsSize",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroups_Statuses_UnitStatusId",
                table: "EnterpriseGroups",
                column: "UnitStatusId",
                principalTable: "Statuses",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_EnterpriseGroupsHistory_UnitsSize_SizeId",
                table: "EnterpriseGroupsHistory",
                column: "SizeId",
                principalTable: "UnitsSize",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnitHistory_UnitsSize_SizeId",
                table: "StatisticalUnitHistory",
                column: "SizeId",
                principalTable: "UnitsSize",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_ReorgTypes_ReorgTypeId",
                table: "StatisticalUnits",
                column: "ReorgTypeId",
                principalTable: "ReorgTypes",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_UnitsSize_SizeId",
                table: "StatisticalUnits",
                column: "SizeId",
                principalTable: "UnitsSize",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_StatisticalUnits_Statuses_UnitStatusId",
                table: "StatisticalUnits",
                column: "UnitStatusId",
                principalTable: "Statuses",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_ReorgTypes_ReorgTypeId",
                table: "EnterpriseGroups");

            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_UnitsSize_SizeId",
                table: "EnterpriseGroups");

            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroups_Statuses_UnitStatusId",
                table: "EnterpriseGroups");

            migrationBuilder.DropForeignKey(
                name: "FK_EnterpriseGroupsHistory_UnitsSize_SizeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnitHistory_UnitsSize_SizeId",
                table: "StatisticalUnitHistory");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_ReorgTypes_ReorgTypeId",
                table: "StatisticalUnits");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_UnitsSize_SizeId",
                table: "StatisticalUnits");

            migrationBuilder.DropForeignKey(
                name: "FK_StatisticalUnits_Statuses_UnitStatusId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_ReorgTypeId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_SizeId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnits_UnitStatusId",
                table: "StatisticalUnits");

            migrationBuilder.DropIndex(
                name: "IX_StatisticalUnitHistory_SizeId",
                table: "StatisticalUnitHistory");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroupsHistory_SizeId",
                table: "EnterpriseGroupsHistory");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_ReorgTypeId",
                table: "EnterpriseGroups");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_SizeId",
                table: "EnterpriseGroups");

            migrationBuilder.DropIndex(
                name: "IX_EnterpriseGroups_UnitStatusId",
                table: "EnterpriseGroups");

            migrationBuilder.RenameColumn(
                name: "SizeId",
                table: "StatisticalUnits",
                newName: "Size");

            migrationBuilder.RenameColumn(
                name: "SizeId",
                table: "StatisticalUnitHistory",
                newName: "Size");

            migrationBuilder.RenameColumn(
                name: "SizeId",
                table: "EnterpriseGroupsHistory",
                newName: "Size");

            migrationBuilder.RenameColumn(
                name: "SizeId",
                table: "EnterpriseGroups",
                newName: "Size");
        }
    }
}
