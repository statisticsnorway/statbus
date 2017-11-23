using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class UserRoles : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ActivityCategoryRoles");

            migrationBuilder.CreateTable(
                name: "ActivityCategoryUsers",
                columns: table => new
                {
                    User_Id = table.Column<string>(nullable: false),
                    ActivityCategory_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategoryUsers", x => new { x.User_Id, x.ActivityCategory_Id });
                    table.ForeignKey(
                        name: "FK_ActivityCategoryUsers_ActivityCategories_ActivityCategory_Id",
                        column: x => x.ActivityCategory_Id,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityCategoryUsers_AspNetUsers_User_Id",
                        column: x => x.User_Id,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ActivityCategoryUsers_ActivityCategory_Id",
                table: "ActivityCategoryUsers",
                column: "ActivityCategory_Id");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ActivityCategoryUsers");

            migrationBuilder.CreateTable(
                name: "ActivityCategoryRoles",
                columns: table => new
                {
                    Role_Id = table.Column<string>(nullable: false),
                    Activity_Category_Id = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ActivityCategoryRoles", x => new { x.Role_Id, x.Activity_Category_Id });
                    table.ForeignKey(
                        name: "FK_ActivityCategoryRoles_ActivityCategories_Activity_Category_Id",
                        column: x => x.Activity_Category_Id,
                        principalTable: "ActivityCategories",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ActivityCategoryRoles_AspNetRoles_Role_Id",
                        column: x => x.Role_Id,
                        principalTable: "AspNetRoles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ActivityCategoryRoles_Activity_Category_Id",
                table: "ActivityCategoryRoles",
                column: "Activity_Category_Id");
        }
    }
}
