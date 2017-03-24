using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using nscreg.Data;
using nscreg.Data.Constants;

namespace nscreg.Data.Migrations
{
    [DbContext(typeof(NSCRegDbContext))]
    partial class NSCRegDbContextModelSnapshot : ModelSnapshot
    {
        protected override void BuildModel(ModelBuilder modelBuilder)
        {
            modelBuilder
                .HasAnnotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.SerialColumn)
                .HasAnnotation("ProductVersion", "1.1.0-rtm-22752");

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

            modelBuilder.Entity("nscreg.Data.Entities.Activity", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd()
                        .HasColumnName("Id");

                    b.Property<int>("ActivityRevx")
                        .HasColumnName("Activity_Revx");

                    b.Property<int>("ActivityRevy")
                        .HasColumnName("Activity_Revy");

                    b.Property<int>("ActivityType")
                        .HasColumnName("Activity_Type");

                    b.Property<int>("ActivityYear")
                        .HasColumnName("Activity_Year");

                    b.Property<int>("Employees")
                        .HasColumnName("Employees");

                    b.Property<DateTime>("IdDate")
                        .HasColumnName("Id_Date");

                    b.Property<decimal>("Turnover")
                        .HasColumnName("Turnover");

                    b.Property<string>("UpdatedBy")
                        .IsRequired()
                        .HasColumnName("Updated_By");

                    b.Property<DateTime>("UpdatedDate")
                        .HasColumnName("Updated_Date");

                    b.HasKey("Id");

                    b.HasIndex("UpdatedBy");

                    b.ToTable("Activities");
                });

            modelBuilder.Entity("nscreg.Data.Entities.ActivityStatisticalUnit", b =>
                {
                    b.Property<int>("UnitId")
                        .HasColumnName("Unit_Id");

                    b.Property<int>("ActivityId")
                        .HasColumnName("Activity_Id");

                    b.HasKey("UnitId", "ActivityId");

                    b.HasIndex("ActivityId");

                    b.ToTable("ActivityStatisticalUnits");
                });

            modelBuilder.Entity("nscreg.Data.Entities.Address", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd()
                        .HasColumnName("Address_id");

                    b.Property<string>("AddressPart1")
                        .HasColumnName("Address_part1");

                    b.Property<string>("AddressPart2")
                        .HasColumnName("Address_part2");

                    b.Property<string>("AddressPart3")
                        .HasColumnName("Address_part3");

                    b.Property<string>("AddressPart4")
                        .HasColumnName("Address_part4");

                    b.Property<string>("AddressPart5")
                        .HasColumnName("Address_part5");

                    b.Property<string>("GeographicalCodes")
                        .HasColumnName("Geographical_codes");

                    b.Property<string>("GpsCoordinates")
                        .HasColumnName("GPS_coordinates");

                    b.HasKey("Id");

                    b.ToTable("Address");
                });

            modelBuilder.Entity("nscreg.Data.Entities.EnterpriseGroup", b =>
                {
                    b.Property<int>("RegId")
                        .ValueGeneratedOnAdd();

                    b.Property<int?>("ActualAddressId");

                    b.Property<int?>("AddressId");

                    b.Property<string>("ContactPerson");

                    b.Property<string>("DataSource");

                    b.Property<string>("EmailAddress");

                    b.Property<int>("Employees");

                    b.Property<DateTime>("EmployeesDate");

                    b.Property<int>("EmployeesFte");

                    b.Property<DateTime>("EmployeesYear");

                    b.Property<DateTime>("EndPeriod");

                    b.Property<string>("EntGroupType");

                    b.Property<int>("ExternalId");

                    b.Property<DateTime>("ExternalIdDate");

                    b.Property<int>("ExternalIdType");

                    b.Property<bool>("IsDeleted");

                    b.Property<DateTime>("LiqDateEnd");

                    b.Property<DateTime>("LiqDateStart");

                    b.Property<string>("LiqReason");

                    b.Property<string>("Name");

                    b.Property<string>("Notes");

                    b.Property<int?>("ParrentId");

                    b.Property<int>("PostalAddressId");

                    b.Property<DateTime>("RegIdDate");

                    b.Property<DateTime>("RegistrationDate");

                    b.Property<string>("RegistrationReason");

                    b.Property<DateTime>("ReorgDate");

                    b.Property<string>("ReorgReferences");

                    b.Property<string>("ReorgTypeCode");

                    b.Property<string>("ShortName");

                    b.Property<DateTime>("StartPeriod");

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

                    b.Property<decimal>("Turnover");

                    b.Property<DateTime>("TurnoverYear");

                    b.Property<string>("WebAddress");

                    b.HasKey("RegId");

                    b.HasIndex("ActualAddressId");

                    b.HasIndex("AddressId");

                    b.HasIndex("ParrentId");

                    b.ToTable("EnterpriseGroups");
                });

            modelBuilder.Entity("nscreg.Data.Entities.Region", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd();

                    b.Property<bool>("IsDeleted")
                        .ValueGeneratedOnAdd()
                        .HasDefaultValue(false);

                    b.Property<string>("Name")
                        .IsRequired();

                    b.HasKey("Id");

                    b.HasIndex("Name")
                        .IsUnique();

                    b.ToTable("Regions");
                });

            modelBuilder.Entity("nscreg.Data.Entities.Role", b =>
                {
                    b.Property<string>("Id")
                        .ValueGeneratedOnAdd();

                    b.Property<string>("AccessToSystemFunctions");

                    b.Property<string>("ConcurrencyStamp")
                        .IsConcurrencyToken();

                    b.Property<string>("Description");

                    b.Property<string>("Name")
                        .HasMaxLength(256);

                    b.Property<string>("NormalizedName")
                        .HasMaxLength(256);

                    b.Property<string>("StandardDataAccess");

                    b.Property<int>("Status");

                    b.HasKey("Id");

                    b.HasIndex("NormalizedName")
                        .IsUnique()
                        .HasName("RoleNameIndex");

                    b.ToTable("AspNetRoles");
                });

            modelBuilder.Entity("nscreg.Data.Entities.StatisticalUnit", b =>
                {
                    b.Property<int>("RegId")
                        .ValueGeneratedOnAdd();

                    b.Property<int?>("ActualAddressId");

                    b.Property<int?>("AddressId");

                    b.Property<string>("Classified");

                    b.Property<string>("ContactPerson");

                    b.Property<string>("DataSource");

                    b.Property<string>("Discriminator")
                        .IsRequired();

                    b.Property<string>("EmailAddress");

                    b.Property<int>("Employees");

                    b.Property<DateTime>("EmployeesDate");

                    b.Property<DateTime>("EmployeesYear");

                    b.Property<DateTime>("EndPeriod");

                    b.Property<int>("ExternalId");

                    b.Property<DateTime>("ExternalIdDate");

                    b.Property<int>("ExternalIdType");

                    b.Property<string>("ForeignParticipation");

                    b.Property<bool>("FreeEconZone");

                    b.Property<bool>("IsDeleted");

                    b.Property<string>("LiqDate");

                    b.Property<string>("LiqReason");

                    b.Property<string>("Name");

                    b.Property<string>("Notes");

                    b.Property<int>("NumOfPeople");

                    b.Property<int?>("ParrentId");

                    b.Property<int>("PostalAddressId");

                    b.Property<int>("RefNo");

                    b.Property<DateTime>("RegIdDate");

                    b.Property<int?>("RegMainActivityId");

                    b.Property<DateTime>("RegistrationDate");

                    b.Property<string>("RegistrationReason");

                    b.Property<DateTime>("ReorgDate");

                    b.Property<string>("ReorgReferences");

                    b.Property<string>("ReorgTypeCode");

                    b.Property<string>("ShortName");

                    b.Property<DateTime>("StartPeriod");

                    b.Property<int>("StatId");

                    b.Property<DateTime>("StatIdDate");

                    b.Property<int>("Status");

                    b.Property<DateTime>("StatusDate");

                    b.Property<string>("SuspensionEnd");

                    b.Property<string>("SuspensionStart");

                    b.Property<DateTime>("TaxRegDate");

                    b.Property<int>("TaxRegId");

                    b.Property<string>("TelephoneNo");

                    b.Property<DateTime>("TurnoveDate");

                    b.Property<decimal>("Turnover");

                    b.Property<DateTime>("TurnoverYear");

                    b.Property<string>("WebAddress");

                    b.HasKey("RegId");

                    b.HasIndex("ActualAddressId");

                    b.HasIndex("AddressId");

                    b.HasIndex("ParrentId");

                    b.HasIndex("RegMainActivityId");

                    b.ToTable("StatisticalUnits");

                    b.HasDiscriminator<string>("Discriminator").HasValue("StatisticalUnit");
                });

            modelBuilder.Entity("nscreg.Data.Entities.User", b =>
                {
                    b.Property<string>("Id")
                        .ValueGeneratedOnAdd();

                    b.Property<int>("AccessFailedCount");

                    b.Property<string>("ConcurrencyStamp")
                        .IsConcurrencyToken();

                    b.Property<DateTime>("CreationDate");

                    b.Property<string>("DataAccess");

                    b.Property<string>("Description");

                    b.Property<string>("Email")
                        .HasMaxLength(256);

                    b.Property<bool>("EmailConfirmed");

                    b.Property<bool>("LockoutEnabled");

                    b.Property<DateTimeOffset?>("LockoutEnd");

                    b.Property<string>("Name");

                    b.Property<string>("NormalizedEmail")
                        .HasMaxLength(256);

                    b.Property<string>("NormalizedUserName")
                        .HasMaxLength(256);

                    b.Property<string>("PasswordHash");

                    b.Property<string>("PhoneNumber");

                    b.Property<bool>("PhoneNumberConfirmed");

                    b.Property<int?>("RegionId");

                    b.Property<string>("SecurityStamp");

                    b.Property<int>("Status");

                    b.Property<DateTime?>("SuspensionDate");

                    b.Property<bool>("TwoFactorEnabled");

                    b.Property<string>("UserName")
                        .HasMaxLength(256);

                    b.HasKey("Id");

                    b.HasIndex("NormalizedEmail")
                        .HasName("EmailIndex");

                    b.HasIndex("NormalizedUserName")
                        .IsUnique()
                        .HasName("UserNameIndex");

                    b.HasIndex("RegionId");

                    b.ToTable("AspNetUsers");
                });

            modelBuilder.Entity("nscreg.Data.Entities.EnterpriseUnit", b =>
                {
                    b.HasBaseType("nscreg.Data.Entities.StatisticalUnit");

                    b.Property<string>("ActualMainActivity1");

                    b.Property<string>("ActualMainActivity2");

                    b.Property<string>("ActualMainActivityDate");

                    b.Property<bool>("Commercial");

                    b.Property<int?>("EntGroupId");

                    b.Property<DateTime>("EntGroupIdDate");

                    b.Property<string>("EntGroupRole");

                    b.Property<string>("ForeignCapitalCurrency");

                    b.Property<string>("ForeignCapitalShare");

                    b.Property<string>("InstSectorCode");

                    b.Property<string>("MunCapitalShare");

                    b.Property<string>("PrivCapitalShare");

                    b.Property<string>("StateCapitalShare");

                    b.Property<string>("TotalCapital");

                    b.HasIndex("EntGroupId");

                    b.ToTable("EnterpriseUnits");

                    b.HasDiscriminator().HasValue("EnterpriseUnit");
                });

            modelBuilder.Entity("nscreg.Data.Entities.LegalUnit", b =>
                {
                    b.HasBaseType("nscreg.Data.Entities.StatisticalUnit");

                    b.Property<string>("ActualMainActivity1");

                    b.Property<string>("ActualMainActivity2");

                    b.Property<string>("ActualMainActivityDate");

                    b.Property<DateTime>("EntRegIdDate");

                    b.Property<int?>("EnterpriseGroupRegId");

                    b.Property<int?>("EnterpriseRegId");

                    b.Property<string>("ForeignCapitalCurrency");

                    b.Property<string>("ForeignCapitalShare");

                    b.Property<string>("Founders");

                    b.Property<string>("InstSectorCode");

                    b.Property<string>("LegalForm");

                    b.Property<bool>("Market");

                    b.Property<string>("MunCapitalShare");

                    b.Property<string>("Owner");

                    b.Property<string>("PrivCapitalShare");

                    b.Property<string>("StateCapitalShare");

                    b.Property<string>("TotalCapital");

                    b.HasIndex("EnterpriseGroupRegId");

                    b.HasIndex("EnterpriseRegId");

                    b.ToTable("LegalUnits");

                    b.HasDiscriminator().HasValue("LegalUnit");
                });

            modelBuilder.Entity("nscreg.Data.Entities.LocalUnit", b =>
                {
                    b.HasBaseType("nscreg.Data.Entities.StatisticalUnit");

                    b.Property<int?>("EnterpriseUnitRegId");

                    b.Property<int>("LegalUnitId");

                    b.Property<DateTime>("LegalUnitIdDate");

                    b.HasIndex("EnterpriseUnitRegId");

                    b.ToTable("LocalUnits");

                    b.HasDiscriminator().HasValue("LocalUnit");
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

            modelBuilder.Entity("nscreg.Data.Entities.Activity", b =>
                {
                    b.HasOne("nscreg.Data.Entities.User", "UpdatedByUser")
                        .WithMany()
                        .HasForeignKey("UpdatedBy")
                        .OnDelete(DeleteBehavior.Cascade);
                });

            modelBuilder.Entity("nscreg.Data.Entities.ActivityStatisticalUnit", b =>
                {
                    b.HasOne("nscreg.Data.Entities.Activity", "Activity")
                        .WithMany("ActivitiesUnits")
                        .HasForeignKey("ActivityId")
                        .OnDelete(DeleteBehavior.Cascade);

                    b.HasOne("nscreg.Data.Entities.StatisticalUnit", "Unit")
                        .WithMany("ActivitiesUnits")
                        .HasForeignKey("UnitId")
                        .OnDelete(DeleteBehavior.Cascade);
                });

            modelBuilder.Entity("nscreg.Data.Entities.EnterpriseGroup", b =>
                {
                    b.HasOne("nscreg.Data.Entities.Address", "ActualAddress")
                        .WithMany()
                        .HasForeignKey("ActualAddressId");

                    b.HasOne("nscreg.Data.Entities.Address", "Address")
                        .WithMany()
                        .HasForeignKey("AddressId");

                    b.HasOne("nscreg.Data.Entities.EnterpriseGroup", "Parrent")
                        .WithMany()
                        .HasForeignKey("ParrentId");
                });

            modelBuilder.Entity("nscreg.Data.Entities.StatisticalUnit", b =>
                {
                    b.HasOne("nscreg.Data.Entities.Address", "ActualAddress")
                        .WithMany()
                        .HasForeignKey("ActualAddressId");

                    b.HasOne("nscreg.Data.Entities.Address", "Address")
                        .WithMany()
                        .HasForeignKey("AddressId");

                    b.HasOne("nscreg.Data.Entities.StatisticalUnit", "Parrent")
                        .WithMany()
                        .HasForeignKey("ParrentId");

                    b.HasOne("nscreg.Data.Entities.Activity", "RegMainActivity")
                        .WithMany()
                        .HasForeignKey("RegMainActivityId");
                });

            modelBuilder.Entity("nscreg.Data.Entities.User", b =>
                {
                    b.HasOne("nscreg.Data.Entities.Region", "Region")
                        .WithMany()
                        .HasForeignKey("RegionId");
                });

            modelBuilder.Entity("nscreg.Data.Entities.EnterpriseUnit", b =>
                {
                    b.HasOne("nscreg.Data.Entities.EnterpriseGroup", "EnterpriseGroup")
                        .WithMany("EnterpriseUnits")
                        .HasForeignKey("EntGroupId");
                });

            modelBuilder.Entity("nscreg.Data.Entities.LegalUnit", b =>
                {
                    b.HasOne("nscreg.Data.Entities.EnterpriseGroup", "EnterpriseGroup")
                        .WithMany("LegalUnits")
                        .HasForeignKey("EnterpriseGroupRegId");

                    b.HasOne("nscreg.Data.Entities.EnterpriseUnit", "EnterpriseUnit")
                        .WithMany("LegalUnits")
                        .HasForeignKey("EnterpriseRegId");
                });

            modelBuilder.Entity("nscreg.Data.Entities.LocalUnit", b =>
                {
                    b.HasOne("nscreg.Data.Entities.EnterpriseUnit", "EnterpriseUnit")
                        .WithMany("LocalUnits")
                        .HasForeignKey("EnterpriseUnitRegId");
                });
        }
    }
}
