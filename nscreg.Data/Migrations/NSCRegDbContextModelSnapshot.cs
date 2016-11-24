using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using nscreg.Data;

namespace nscreg.Data.Migrations
{
    [DbContext(typeof(NSCRegDbContext))]
    partial class NSCRegDbContextModelSnapshot : ModelSnapshot
    {
        protected override void BuildModel(ModelBuilder modelBuilder)
        {
            modelBuilder
                .HasAnnotation("ProductVersion", "1.0.1");

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityRoleClaim<string>", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd();

                    b.Property<string>("ClaimType");

                    b.Property<string>("ClaimValue");

                    b.Property<string>("RoleId")
                        .IsRequired();

                    b.HasKey("Id");

                    b.HasIndex("RoleId");

                    b.ToTable("AspNetRoleClaims");
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityUserClaim<string>", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd();

                    b.Property<string>("ClaimType");

                    b.Property<string>("ClaimValue");

                    b.Property<string>("UserId")
                        .IsRequired();

                    b.HasKey("Id");

                    b.HasIndex("UserId");

                    b.ToTable("AspNetUserClaims");
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityUserLogin<string>", b =>
                {
                    b.Property<string>("LoginProvider");

                    b.Property<string>("ProviderKey");

                    b.Property<string>("ProviderDisplayName");

                    b.Property<string>("UserId")
                        .IsRequired();

                    b.HasKey("LoginProvider", "ProviderKey");

                    b.HasIndex("UserId");

                    b.ToTable("AspNetUserLogins");
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityUserRole<string>", b =>
                {
                    b.Property<string>("UserId");

                    b.Property<string>("RoleId");

                    b.HasKey("UserId", "RoleId");

                    b.HasIndex("RoleId");

                    b.HasIndex("UserId");

                    b.ToTable("AspNetUserRoles");
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityUserToken<string>", b =>
                {
                    b.Property<string>("UserId");

                    b.Property<string>("LoginProvider");

                    b.Property<string>("Name");

                    b.Property<string>("Value");

                    b.HasKey("UserId", "LoginProvider", "Name");

                    b.ToTable("AspNetUserTokens");
                });

            modelBuilder.Entity("nscreg.Data.Entities.EnterpriseGroup", b =>
                {
                    b.Property<int>("RegId")
                        .ValueGeneratedOnAdd();

                    b.Property<string>("ActualAddressId");

                    b.Property<string>("AddressId");

                    b.Property<string>("ContactPerson");

                    b.Property<string>("DataSource");

                    b.Property<string>("EmailAddress");

                    b.Property<int>("Employees");

                    b.Property<DateTime>("EmployeesDate");

                    b.Property<int>("EmployeesFte");

                    b.Property<DateTime>("EmployeesYear");

                    b.Property<string>("EntGroupType");

                    b.Property<int>("ExternalId");

                    b.Property<DateTime>("ExternalIdDate");

                    b.Property<string>("ExternalIdType");

                    b.Property<DateTime>("LiqDateEnd");

                    b.Property<DateTime>("LiqDateStart");

                    b.Property<string>("LiqReason");

                    b.Property<string>("Name");

                    b.Property<string>("Notes");

                    b.Property<string>("PostalAddressId");

                    b.Property<DateTime>("RegIdDate");

                    b.Property<DateTime>("RegistrationDate");

                    b.Property<string>("RegistrationReason");

                    b.Property<DateTime>("ReorgDate");

                    b.Property<string>("ReorgReferences");

                    b.Property<string>("ReorgTypeCode");

                    b.Property<string>("ShortName");

                    b.Property<int>("StatId");

                    b.Property<DateTime>("StatIdDate");

                    b.Property<string>("Status");

                    b.Property<DateTime>("StatusDate");

                    b.Property<string>("SuspensionEnd");

                    b.Property<string>("SuspensionStart");

                    b.Property<DateTime>("TaxRegDate");

                    b.Property<int>("TaxRegId");

                    b.Property<string>("TelephoneNo");

                    b.Property<DateTime>("TurnoveDate");

                    b.Property<string>("Turnover");

                    b.Property<DateTime>("TurnoverYear");

                    b.Property<string>("WebAddress");

                    b.HasKey("RegId");

                    b.ToTable("EnterpriseGroups");
                });

            modelBuilder.Entity("nscreg.Data.Entities.EnterpriseUnit", b =>
                {
                    b.Property<int>("RegId")
                        .ValueGeneratedOnAdd();

                    b.Property<string>("ActualAddressId");

                    b.Property<string>("ActualMainActivity1");

                    b.Property<string>("ActualMainActivity2");

                    b.Property<string>("ActualMainActivityDate");

                    b.Property<int>("AddressId");

                    b.Property<string>("Classified");

                    b.Property<string>("Commercial");

                    b.Property<string>("ContactPerson");

                    b.Property<string>("DataSource");

                    b.Property<string>("EmailAddress");

                    b.Property<int>("Employees");

                    b.Property<DateTime>("EmployeesDate");

                    b.Property<DateTime>("EmployeesYear");

                    b.Property<int>("EntGroupId");

                    b.Property<DateTime>("EntGroupIdDate");

                    b.Property<string>("EntGroupRole");

                    b.Property<int>("ExternalId");

                    b.Property<DateTime>("ExternalIdDate");

                    b.Property<int>("ExternalIdType");

                    b.Property<string>("ForeignCapitalCurrency");

                    b.Property<string>("ForeignCapitalShare");

                    b.Property<string>("ForeignParticipation");

                    b.Property<bool>("FreeEconZone");

                    b.Property<string>("InstSectorCode");

                    b.Property<string>("LiqDate");

                    b.Property<string>("LiqReason");

                    b.Property<string>("MunCapitalShare");

                    b.Property<string>("Name");

                    b.Property<string>("Notes");

                    b.Property<int>("NumOfPeople");

                    b.Property<int>("PostalAddressId");

                    b.Property<string>("PrivCapitalShare");

                    b.Property<int>("RefNo");

                    b.Property<DateTime>("RegIdDate");

                    b.Property<string>("RegMainActivity");

                    b.Property<DateTime>("RegistrationDate");

                    b.Property<string>("RegistrationReason");

                    b.Property<DateTime>("ReorgDate");

                    b.Property<string>("ReorgReferences");

                    b.Property<string>("ReorgTypeCode");

                    b.Property<string>("ShortName");

                    b.Property<int>("StatId");

                    b.Property<DateTime>("StatIdDate");

                    b.Property<string>("StateCapitalShare");

                    b.Property<string>("Status");

                    b.Property<DateTime>("StatusDate");

                    b.Property<string>("SuspensionEnd");

                    b.Property<string>("SuspensionStart");

                    b.Property<DateTime>("TaxRegDate");

                    b.Property<int>("TaxRegId");

                    b.Property<string>("TelephoneNo");

                    b.Property<string>("TotalCapital");

                    b.Property<DateTime>("TurnoveDate");

                    b.Property<string>("Turnover");

                    b.Property<DateTime>("TurnoverYear");

                    b.Property<string>("WebAddress");

                    b.HasKey("RegId");

                    b.ToTable("EnterpriseUnits");
                });

            modelBuilder.Entity("nscreg.Data.Entities.LegalUnit", b =>
                {
                    b.Property<int>("RegId")
                        .ValueGeneratedOnAdd();

                    b.Property<string>("ActualAddressId");

                    b.Property<string>("ActualMainActivity1");

                    b.Property<string>("ActualMainActivity2");

                    b.Property<string>("ActualMainActivityDate");

                    b.Property<int>("AddressId");

                    b.Property<string>("Classified");

                    b.Property<string>("ContactPerson");

                    b.Property<string>("DataSource");

                    b.Property<string>("EmailAddress");

                    b.Property<int>("Employees");

                    b.Property<DateTime>("EmployeesDate");

                    b.Property<DateTime>("EmployeesYear");

                    b.Property<DateTime>("EntRegIdDate");

                    b.Property<int>("EnterpriseRegId");

                    b.Property<int>("ExternalId");

                    b.Property<DateTime>("ExternalIdDate");

                    b.Property<int>("ExternalIdType");

                    b.Property<string>("ForeignCapitalCurrency");

                    b.Property<string>("ForeignCapitalShare");

                    b.Property<string>("ForeignParticipation");

                    b.Property<string>("Founders");

                    b.Property<bool>("FreeEconZone");

                    b.Property<string>("InstSectorCode");

                    b.Property<string>("LegalForm");

                    b.Property<string>("LiqDate");

                    b.Property<string>("LiqReason");

                    b.Property<string>("Market");

                    b.Property<string>("MunCapitalShare");

                    b.Property<string>("Name");

                    b.Property<string>("Notes");

                    b.Property<int>("NumOfPeople");

                    b.Property<string>("Owner");

                    b.Property<int>("PostalAddressId");

                    b.Property<string>("PrivCapitalShare");

                    b.Property<int>("RefNo");

                    b.Property<DateTime>("RegIdDate");

                    b.Property<string>("RegMainActivity");

                    b.Property<DateTime>("RegistrationDate");

                    b.Property<string>("RegistrationReason");

                    b.Property<DateTime>("ReorgDate");

                    b.Property<string>("ReorgReferences");

                    b.Property<string>("ReorgTypeCode");

                    b.Property<string>("ShortName");

                    b.Property<int>("StatId");

                    b.Property<DateTime>("StatIdDate");

                    b.Property<string>("StateCapitalShare");

                    b.Property<string>("Status");

                    b.Property<DateTime>("StatusDate");

                    b.Property<string>("SuspensionEnd");

                    b.Property<string>("SuspensionStart");

                    b.Property<DateTime>("TaxRegDate");

                    b.Property<int>("TaxRegId");

                    b.Property<string>("TelephoneNo");

                    b.Property<string>("TotalCapital");

                    b.Property<DateTime>("TurnoveDate");

                    b.Property<string>("Turnover");

                    b.Property<DateTime>("TurnoverYear");

                    b.Property<string>("WebAddress");

                    b.HasKey("RegId");

                    b.ToTable("LegalUnits");
                });

            modelBuilder.Entity("nscreg.Data.Entities.LocalUnit", b =>
                {
                    b.Property<int>("RegId")
                        .ValueGeneratedOnAdd();

                    b.Property<string>("ActualAddressId");

                    b.Property<int>("AddressId");

                    b.Property<string>("Classified");

                    b.Property<string>("ContactPerson");

                    b.Property<string>("DataSource");

                    b.Property<string>("EmailAddress");

                    b.Property<int>("Employees");

                    b.Property<DateTime>("EmployeesDate");

                    b.Property<DateTime>("EmployeesYear");

                    b.Property<int>("ExternalId");

                    b.Property<DateTime>("ExternalIdDate");

                    b.Property<int>("ExternalIdType");

                    b.Property<string>("ForeignParticipation");

                    b.Property<bool>("FreeEconZone");

                    b.Property<int>("LegalUnitId");

                    b.Property<DateTime>("LegalUnitIdDate");

                    b.Property<string>("LiqDate");

                    b.Property<string>("LiqReason");

                    b.Property<string>("Name");

                    b.Property<string>("Notes");

                    b.Property<int>("NumOfPeople");

                    b.Property<int>("PostalAddressId");

                    b.Property<int>("RefNo");

                    b.Property<DateTime>("RegIdDate");

                    b.Property<string>("RegMainActivity");

                    b.Property<DateTime>("RegistrationDate");

                    b.Property<string>("RegistrationReason");

                    b.Property<DateTime>("ReorgDate");

                    b.Property<string>("ReorgReferences");

                    b.Property<string>("ReorgTypeCode");

                    b.Property<string>("ShortName");

                    b.Property<int>("StatId");

                    b.Property<DateTime>("StatIdDate");

                    b.Property<string>("Status");

                    b.Property<DateTime>("StatusDate");

                    b.Property<string>("SuspensionEnd");

                    b.Property<string>("SuspensionStart");

                    b.Property<DateTime>("TaxRegDate");

                    b.Property<int>("TaxRegId");

                    b.Property<string>("TelephoneNo");

                    b.Property<DateTime>("TurnoveDate");

                    b.Property<string>("Turnover");

                    b.Property<DateTime>("TurnoverYear");

                    b.Property<string>("WebAddress");

                    b.HasKey("RegId");

                    b.ToTable("LocalUnits");
                });

            modelBuilder.Entity("nscreg.Data.Entities.Role", b =>
                {
                    b.Property<string>("Id");

                    b.Property<string>("AccessToSystemFunctions");

                    b.Property<string>("ConcurrencyStamp")
                        .IsConcurrencyToken();

                    b.Property<string>("Description");

                    b.Property<string>("Name")
                        .HasAnnotation("MaxLength", 256);

                    b.Property<string>("NormalizedName")
                        .HasAnnotation("MaxLength", 256);

                    b.Property<string>("StandardDataAccess");

                    b.HasKey("Id");

                    b.HasIndex("NormalizedName")
                        .HasName("RoleNameIndex");

                    b.ToTable("AspNetRoles");
                });

            modelBuilder.Entity("nscreg.Data.Entities.User", b =>
                {
                    b.Property<string>("Id");

                    b.Property<int>("AccessFailedCount");

                    b.Property<string>("ConcurrencyStamp")
                        .IsConcurrencyToken();

                    b.Property<string>("DataAccess");

                    b.Property<string>("Description");

                    b.Property<string>("Email")
                        .HasAnnotation("MaxLength", 256);

                    b.Property<bool>("EmailConfirmed");

                    b.Property<bool>("LockoutEnabled");

                    b.Property<DateTimeOffset?>("LockoutEnd");

                    b.Property<string>("Name");

                    b.Property<string>("NormalizedEmail")
                        .HasAnnotation("MaxLength", 256);

                    b.Property<string>("NormalizedUserName")
                        .HasAnnotation("MaxLength", 256);

                    b.Property<string>("PasswordHash");

                    b.Property<string>("PhoneNumber");

                    b.Property<bool>("PhoneNumberConfirmed");

                    b.Property<string>("SecurityStamp");

                    b.Property<int>("Status");

                    b.Property<bool>("TwoFactorEnabled");

                    b.Property<string>("UserName")
                        .HasAnnotation("MaxLength", 256);

                    b.HasKey("Id");

                    b.HasIndex("NormalizedEmail")
                        .HasName("EmailIndex");

                    b.HasIndex("NormalizedUserName")
                        .IsUnique()
                        .HasName("UserNameIndex");

                    b.ToTable("AspNetUsers");
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityRoleClaim<string>", b =>
                {
                    b.HasOne("nscreg.Data.Entities.Role")
                        .WithMany("Claims")
                        .HasForeignKey("RoleId")
                        .OnDelete(DeleteBehavior.Cascade);
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityUserClaim<string>", b =>
                {
                    b.HasOne("nscreg.Data.Entities.User")
                        .WithMany("Claims")
                        .HasForeignKey("UserId")
                        .OnDelete(DeleteBehavior.Cascade);
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityUserLogin<string>", b =>
                {
                    b.HasOne("nscreg.Data.Entities.User")
                        .WithMany("Logins")
                        .HasForeignKey("UserId")
                        .OnDelete(DeleteBehavior.Cascade);
                });

            modelBuilder.Entity("Microsoft.AspNetCore.Identity.EntityFrameworkCore.IdentityUserRole<string>", b =>
                {
                    b.HasOne("nscreg.Data.Entities.Role")
                        .WithMany("Users")
                        .HasForeignKey("RoleId")
                        .OnDelete(DeleteBehavior.Cascade);

                    b.HasOne("nscreg.Data.Entities.User")
                        .WithMany("Roles")
                        .HasForeignKey("UserId")
                        .OnDelete(DeleteBehavior.Cascade);
                });
        }
    }
}
