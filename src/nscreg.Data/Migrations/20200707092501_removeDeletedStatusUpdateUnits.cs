using System.Data;
using System.Data.SqlClient;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class removeDeletedStatusUpdateUnits : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // migrationBuilder.Sql("UPDATE StatisticalUnitHistory\r\nSET UnitStatusId = 9 WHERE UnitStatusId = 8\r\nUPDATE StatisticalUnits \r\nSET UnitStatusId = 9 WHERE UnitStatusId = 8\r\nUPDATE EnterpriseGroupsHistory\r\nSET UnitStatusId = 9 WHERE UnitStatusId = 8\r\nUPDATE EnterpriseGroups\r\nSET UnitStatusId = 9 WHERE UnitStatusId = 8\r\nDELETE FROM Statuses  WHERE Code = 8");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                "INSERT INTO Statuses(Name,IsDeleted,NameLanguage1,NameLanguage2,Code) VALUES(N'Deleted',0,N'',N'',N'8')");
        }
    }
}
