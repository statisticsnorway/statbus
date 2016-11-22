using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

namespace nscreg.Data.Migrations
{
    public partial class AddStatisticalUnitsAndDescendants : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "EnterpriseGroups",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGeneratedOnAdd", true),
                    ActualAddressId = table.Column<string>(nullable: true),
                    AddressId = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: false),
                    EmployeesDate = table.Column<DateTime>(nullable: false),
                    EmployeesFte = table.Column<int>(nullable: false),
                    EmployeesYear = table.Column<DateTime>(nullable: false),
                    EntGroupType = table.Column<string>(nullable: true),
                    ExternalId = table.Column<int>(nullable: false),
                    ExternalIdDate = table.Column<DateTime>(nullable: false),
                    ExternalIdType = table.Column<string>(nullable: true),
                    LiqDateEnd = table.Column<DateTime>(nullable: false),
                    LiqDateStart = table.Column<DateTime>(nullable: false),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    PostalAddressId = table.Column<string>(nullable: true),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: false),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    StatId = table.Column<int>(nullable: false),
                    StatIdDate = table.Column<DateTime>(nullable: false),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: false),
                    TaxRegId = table.Column<int>(nullable: false),
                    TelephoneNo = table.Column<string>(nullable: true),
                    TurnoveDate = table.Column<DateTime>(nullable: false),
                    Turnover = table.Column<string>(nullable: true),
                    TurnoverYear = table.Column<DateTime>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseGroups", x => x.RegId);
                });

            migrationBuilder.CreateTable(
                name: "EnterpriseUnits",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGeneratedOnAdd", true),
                    ActualAddressId = table.Column<string>(nullable: true),
                    ActualMainActivity1 = table.Column<string>(nullable: true),
                    ActualMainActivity2 = table.Column<string>(nullable: true),
                    ActualMainActivityDate = table.Column<string>(nullable: true),
                    AddressId = table.Column<int>(nullable: false),
                    Classified = table.Column<string>(nullable: true),
                    Commercial = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: false),
                    EmployeesDate = table.Column<DateTime>(nullable: false),
                    EmployeesYear = table.Column<DateTime>(nullable: false),
                    EntGroupId = table.Column<int>(nullable: false),
                    EntGroupIdDate = table.Column<DateTime>(nullable: false),
                    EntGroupRole = table.Column<string>(nullable: true),
                    ExternalId = table.Column<int>(nullable: false),
                    ExternalIdDate = table.Column<DateTime>(nullable: false),
                    ExternalIdType = table.Column<int>(nullable: false),
                    ForeignCapitalCurrency = table.Column<string>(nullable: true),
                    ForeignCapitalShare = table.Column<string>(nullable: true),
                    ForeignParticipation = table.Column<string>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    InstSectorCode = table.Column<string>(nullable: true),
                    LiqDate = table.Column<string>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    MunCapitalShare = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    NumOfPeople = table.Column<int>(nullable: false),
                    PostalAddressId = table.Column<int>(nullable: false),
                    PrivCapitalShare = table.Column<string>(nullable: true),
                    RefNo = table.Column<int>(nullable: false),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegMainActivity = table.Column<string>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: false),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    StatId = table.Column<int>(nullable: false),
                    StatIdDate = table.Column<DateTime>(nullable: false),
                    StateCapitalShare = table.Column<string>(nullable: true),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: false),
                    TaxRegId = table.Column<int>(nullable: false),
                    TelephoneNo = table.Column<string>(nullable: true),
                    TotalCapital = table.Column<string>(nullable: true),
                    TurnoveDate = table.Column<DateTime>(nullable: false),
                    Turnover = table.Column<string>(nullable: true),
                    TurnoverYear = table.Column<DateTime>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EnterpriseUnits", x => x.RegId);
                });

            migrationBuilder.CreateTable(
                name: "LegalUnits",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGeneratedOnAdd", true),
                    ActualAddressId = table.Column<string>(nullable: true),
                    ActualMainActivity1 = table.Column<string>(nullable: true),
                    ActualMainActivity2 = table.Column<string>(nullable: true),
                    ActualMainActivityDate = table.Column<string>(nullable: true),
                    AddressId = table.Column<int>(nullable: false),
                    Classified = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: false),
                    EmployeesDate = table.Column<DateTime>(nullable: false),
                    EmployeesYear = table.Column<DateTime>(nullable: false),
                    EntRegIdDate = table.Column<DateTime>(nullable: false),
                    EnterpriseRegId = table.Column<int>(nullable: false),
                    ExternalId = table.Column<int>(nullable: false),
                    ExternalIdDate = table.Column<DateTime>(nullable: false),
                    ExternalIdType = table.Column<int>(nullable: false),
                    ForeignCapitalCurrency = table.Column<string>(nullable: true),
                    ForeignCapitalShare = table.Column<string>(nullable: true),
                    ForeignParticipation = table.Column<string>(nullable: true),
                    Founders = table.Column<string>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    InstSectorCode = table.Column<string>(nullable: true),
                    LegalForm = table.Column<string>(nullable: true),
                    LiqDate = table.Column<string>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    Market = table.Column<string>(nullable: true),
                    MunCapitalShare = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    NumOfPeople = table.Column<int>(nullable: false),
                    Owner = table.Column<string>(nullable: true),
                    PostalAddressId = table.Column<int>(nullable: false),
                    PrivCapitalShare = table.Column<string>(nullable: true),
                    RefNo = table.Column<int>(nullable: false),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegMainActivity = table.Column<string>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: false),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    StatId = table.Column<int>(nullable: false),
                    StatIdDate = table.Column<DateTime>(nullable: false),
                    StateCapitalShare = table.Column<string>(nullable: true),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: false),
                    TaxRegId = table.Column<int>(nullable: false),
                    TelephoneNo = table.Column<string>(nullable: true),
                    TotalCapital = table.Column<string>(nullable: true),
                    TurnoveDate = table.Column<DateTime>(nullable: false),
                    Turnover = table.Column<string>(nullable: true),
                    TurnoverYear = table.Column<DateTime>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LegalUnits", x => x.RegId);
                });

            migrationBuilder.CreateTable(
                name: "LocalUnits",
                columns: table => new
                {
                    RegId = table.Column<int>(nullable: false)
                        .Annotation("Npgsql:ValueGeneratedOnAdd", true),
                    ActualAddressId = table.Column<string>(nullable: true),
                    AddressId = table.Column<int>(nullable: false),
                    Classified = table.Column<string>(nullable: true),
                    ContactPerson = table.Column<string>(nullable: true),
                    DataSource = table.Column<string>(nullable: true),
                    EmailAddress = table.Column<string>(nullable: true),
                    Employees = table.Column<int>(nullable: false),
                    EmployeesDate = table.Column<DateTime>(nullable: false),
                    EmployeesYear = table.Column<DateTime>(nullable: false),
                    ExternalId = table.Column<int>(nullable: false),
                    ExternalIdDate = table.Column<DateTime>(nullable: false),
                    ExternalIdType = table.Column<int>(nullable: false),
                    ForeignParticipation = table.Column<string>(nullable: true),
                    FreeEconZone = table.Column<bool>(nullable: false),
                    LegalUnitId = table.Column<int>(nullable: false),
                    LegalUnitIdDate = table.Column<DateTime>(nullable: false),
                    LiqDate = table.Column<string>(nullable: true),
                    LiqReason = table.Column<string>(nullable: true),
                    Name = table.Column<string>(nullable: true),
                    Notes = table.Column<string>(nullable: true),
                    NumOfPeople = table.Column<int>(nullable: false),
                    PostalAddressId = table.Column<int>(nullable: false),
                    RefNo = table.Column<int>(nullable: false),
                    RegIdDate = table.Column<DateTime>(nullable: false),
                    RegMainActivity = table.Column<string>(nullable: true),
                    RegistrationDate = table.Column<DateTime>(nullable: false),
                    RegistrationReason = table.Column<string>(nullable: true),
                    ReorgDate = table.Column<DateTime>(nullable: false),
                    ReorgReferences = table.Column<string>(nullable: true),
                    ReorgTypeCode = table.Column<string>(nullable: true),
                    ShortName = table.Column<string>(nullable: true),
                    StatId = table.Column<int>(nullable: false),
                    StatIdDate = table.Column<DateTime>(nullable: false),
                    Status = table.Column<string>(nullable: true),
                    StatusDate = table.Column<DateTime>(nullable: false),
                    SuspensionEnd = table.Column<string>(nullable: true),
                    SuspensionStart = table.Column<string>(nullable: true),
                    TaxRegDate = table.Column<DateTime>(nullable: false),
                    TaxRegId = table.Column<int>(nullable: false),
                    TelephoneNo = table.Column<string>(nullable: true),
                    TurnoveDate = table.Column<DateTime>(nullable: false),
                    Turnover = table.Column<string>(nullable: true),
                    TurnoverYear = table.Column<DateTime>(nullable: false),
                    WebAddress = table.Column<string>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LocalUnits", x => x.RegId);
                });
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "EnterpriseGroups");

            migrationBuilder.DropTable(
                name: "EnterpriseUnits");

            migrationBuilder.DropTable(
                name: "LegalUnits");

            migrationBuilder.DropTable(
                name: "LocalUnits");
        }
    }
}
