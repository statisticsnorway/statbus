using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class SuspensionsAndLiqDateToDates_ReorgReferencesToInt : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            if (migrationBuilder.ActiveProvider == "Npgsql.EntityFrameworkCore.PostgreSQL")
            {
                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" ADD COLUMN \"SuspensionStart_Tmp\" TIMESTAMP without time zone NULL");
                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" ADD COLUMN \"SuspensionEnd_Tmp\" TIMESTAMP without time zone NULL");
                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" ADD COLUMN \"LiqDate_Tmp\" TIMESTAMP without time zone NULL");

                migrationBuilder.Sql("UPDATE \"StatisticalUnits\" SET \"SuspensionStart_Tmp\" = \"SuspensionStart\"::TIMESTAMP");
                migrationBuilder.Sql("UPDATE \"StatisticalUnits\" SET \"SuspensionEnd_Tmp\" = \"SuspensionEnd\"::TIMESTAMP");
                migrationBuilder.Sql("UPDATE \"StatisticalUnits\" SET \"LiqDate_Tmp\" = \"LiqDate\"::TIMESTAMP");

                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" ALTER COLUMN \"SuspensionStart\" TYPE TIMESTAMP without time zone USING \"SuspensionStart_Tmp\"");
                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" ALTER COLUMN \"SuspensionEnd\" TYPE TIMESTAMP without time zone USING \"SuspensionEnd_Tmp\"");
                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" ALTER COLUMN \"LiqDate\" TYPE TIMESTAMP without time zone USING \"LiqDate_Tmp\"");

                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" DROP COLUMN \"SuspensionStart_Tmp\"");
                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" DROP COLUMN \"SuspensionEnd_Tmp\"");
                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" DROP COLUMN \"LiqDate_Tmp\"");

                migrationBuilder.Sql("ALTER TABLE \"StatisticalUnits\" ALTER COLUMN \"ReorgReferences\" TYPE integer USING \"ReorgReferences\"::integer");
            }
            else
            {
                migrationBuilder.AlterColumn<DateTime>(
                    name: "SuspensionStart",
                    table: "StatisticalUnits",
                    nullable: true,
                    oldClrType: typeof(string),
                    oldNullable: true);

                migrationBuilder.AlterColumn<DateTime>(
                    name: "SuspensionEnd",
                    table: "StatisticalUnits",
                    nullable: true,
                    oldClrType: typeof(string),
                    oldNullable: true);
                migrationBuilder.AlterColumn<DateTime>(
                    name: "LiqDate",
                    table: "StatisticalUnits",
                    nullable: true,
                    oldClrType: typeof(string),
                    oldNullable: true);
                migrationBuilder.AlterColumn<int>(
                    name: "ReorgReferences",
                    table: "StatisticalUnits",
                    nullable: true,
                    oldClrType: typeof(string),
                    oldNullable: true);
            } 
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "SuspensionStart",
                table: "StatisticalUnits",
                nullable: true,
                oldClrType: typeof(DateTime),
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "SuspensionEnd",
                table: "StatisticalUnits",
                nullable: true,
                oldClrType: typeof(DateTime),
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "ReorgReferences",
                table: "StatisticalUnits",
                nullable: true,
                oldClrType: typeof(int),
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "LiqDate",
                table: "StatisticalUnits",
                nullable: true,
                oldClrType: typeof(DateTime),
                oldNullable: true);
        }
    }
}
