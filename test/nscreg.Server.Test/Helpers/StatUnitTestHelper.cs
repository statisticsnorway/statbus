using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Addresses;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.Regions;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Test.Extensions;
using System.Linq;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using Activity = nscreg.Data.Entities.Activity;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;

// ReSharper disable once CheckNamespace
namespace nscreg.Server.Test
{
    public class StatUnitTestHelper
    {
        private const string RegionCode = "41700000000000";
        private const string RegionName = "Kyrgyzstan";
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;

        public StatUnitTestHelper(StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields)
        {
            _analysisRules = analysisRules;
            _mandatoryFields = mandatoryFields;
        }

        public async Task<LegalUnit> CreateLegalUnitAsync(NSCRegDbContext context, List<ActivityM> activities,
            AddressM address, string unitName)
        {
            await new CreateService(context, _analysisRules, _mandatoryFields).CreateLegalUnit(new LegalUnitCreateM
            {
                DataAccess = DbContextExtensions.DataAccessLegalUnit,
                Name = unitName,
                Address = address ?? await CreateAddressAsync(context),
                Activities = activities ?? new List<ActivityM>(),
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = Guid.NewGuid().ToString(),
                ShortName = Guid.NewGuid().ToString(),
                TelephoneNo = Guid.NewGuid().ToString(),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                Status = StatUnitStatuses.Active,
                Persons = new List<PersonM>
                {
                    new PersonM
                    {
                        Role = PersonTypes.Owner
                    }
                }
            }, DbContextExtensions.UserId);

            return context.LegalUnits.FirstOrDefault();
        }

        public async Task CreateLocalUnitAsync(NSCRegDbContext context, List<ActivityM> activities, AddressM address,
            string unitName, int legalUnitRegId)
        {
            await new CreateService(context, _analysisRules, _mandatoryFields).CreateLocalUnit(new LocalUnitCreateM
            {
                DataAccess = DbContextExtensions.DataAccessLocalUnit,
                Name = unitName,
                Address = address ?? await CreateAddressAsync(context),
                Activities = activities ?? await CreateActivitiesAsync(context),
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = Guid.NewGuid().ToString(),
                ShortName = Guid.NewGuid().ToString(),
                TelephoneNo = Guid.NewGuid().ToString(),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                Status = StatUnitStatuses.Active,
                LegalUnitId = legalUnitRegId,
                Persons = new List<PersonM>
                {
                    new PersonM
                    {
                        Role = PersonTypes.Owner
                    }
                }
            }, DbContextExtensions.UserId);
        }

        public async Task CreateEnterpriseUnitAsync(NSCRegDbContext context, List<ActivityM> activities,
            AddressM address, string unitName, int[] legalUnitIds, int? enterpriseGroupId)
        {
            await new CreateService(context, _analysisRules, _mandatoryFields).CreateEnterpriseUnit(new EnterpriseUnitCreateM
            {
                DataAccess = DbContextExtensions.DataAccessEnterpriseUnit,
                Name = unitName,
                Address = address ?? await CreateAddressAsync(context),
                Activities = activities,
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = Guid.NewGuid().ToString(),
                ShortName = Guid.NewGuid().ToString(),
                TelephoneNo = Guid.NewGuid().ToString(),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                Status = StatUnitStatuses.Active,
                LegalUnits = legalUnitIds,
                EntGroupId = enterpriseGroupId,
                Persons = CreatePersons(),
            }, DbContextExtensions.UserId);
        }

        public async Task<EnterpriseGroup> CreateEnterpriseGroupAsync(NSCRegDbContext context, AddressM address,
            string unitName, int[] enterpriseUnitsIds, int[] legalUnitsIds)
        {
            await new CreateService(context, _analysisRules, _mandatoryFields).CreateEnterpriseGroup(new EnterpriseGroupCreateM
            {
                DataAccess = DbContextExtensions.DataAccessEnterpriseGroup,
                Name = unitName,
                Address = address ?? await CreateAddressAsync(context),
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = Guid.NewGuid().ToString(),
                ShortName = Guid.NewGuid().ToString(),
                TelephoneNo = Guid.NewGuid().ToString(),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                EnterpriseUnits = enterpriseUnitsIds,
                LegalUnits = legalUnitsIds
            }, DbContextExtensions.UserId);

            return context.EnterpriseGroups.FirstOrDefault();
        }


        public async Task<AddressM> CreateAddressAsync(NSCRegDbContext context)
        {
            var address = await new AddressService(context).CreateAsync(new AddressModel
            {
                AddressPart1 = Guid.NewGuid().ToString(),
                Region = new RegionM {Code = RegionCode, Name = RegionName}
            });

            return new AddressM
            {
                Id = address.Id,
                AddressPart1 = address.AddressPart1,
                Region = address.Region
            };
        }

        public async Task<List<ActivityM>> CreateActivitiesAsync(NSCRegDbContext context)
        {
            var localActivity = context.Activities.Add(new Activity
            {
                ActivityYear = 2017,
                Employees = 888,
                Turnover = 2000000,
                ActivityRevxCategory = new ActivityCategory
                {
                    Code = "01.13.1",
                    Name = "Activity Category",
                    Section = "A"
                },
                ActivityRevy = 3,
                ActivityType = ActivityTypes.Secondary,
            });
            await context.SaveChangesAsync();

            return new List<ActivityM>
            {
                new ActivityM
                {
                    Id = localActivity.Entity.Id,
                    ActivityYear = localActivity.Entity.ActivityYear,
                    Employees = localActivity.Entity.Employees,
                    Turnover = localActivity.Entity.Turnover,
                    ActivityRevxCategory = new CodeLookupVm()
                    {
                        Code = localActivity.Entity.ActivityRevxCategory.Code,
                        Id = localActivity.Entity.ActivityRevxCategory.Id
                    },
                    ActivityRevy = localActivity.Entity.ActivityRevy,
                    ActivityType = ActivityTypes.Primary,
                }
            };
        }

        private List<PersonM> CreatePersons()
        {
            return new List<PersonM>
            {
                new PersonM
                {
                    Role = PersonTypes.Owner
                }
            };
        }


        public async Task EditLegalUnitAsync(NSCRegDbContext context, List<ActivityM> activities, int unitId,
            string unitNameEdit)
        {
            await new EditService(context, _analysisRules, _mandatoryFields).EditLegalUnit(new LegalUnitEditM
            {
                RegId = unitId,
                Name = unitNameEdit,
                DataAccess = DbContextExtensions.DataAccessLegalUnit,
                Address = await CreateAddressAsync(context),
                Activities = activities ?? new List<ActivityM>(),
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = nameof(LegalUnitCreateM.ContactPerson),
                ShortName = nameof(LegalUnitCreateM.ShortName),
                TelephoneNo = nameof(LegalUnitCreateM.TelephoneNo),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                Status = StatUnitStatuses.Active,
                Persons = new List<PersonM>
                {
                    new PersonM
                    {
                        Role = PersonTypes.Owner
                    }
                }
            }, DbContextExtensions.UserId);
        }

        public async Task EditLocalUnitAsync(NSCRegDbContext context, List<ActivityM> activities, int unitId,
            string unitNameEdit, int legalUnitRegId)
        {
            await new EditService(context, _analysisRules, _mandatoryFields).EditLocalUnit(new LocalUnitEditM
            {
                DataAccess = DbContextExtensions.DataAccessLocalUnit,
                RegId = unitId,
                Name = unitNameEdit,
                Address = await CreateAddressAsync(context),
                Activities = activities,
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = nameof(LegalUnitCreateM.ContactPerson),
                ShortName = nameof(LegalUnitCreateM.ShortName),
                TelephoneNo = nameof(LegalUnitCreateM.TelephoneNo),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                Status = StatUnitStatuses.Active,
                LegalUnitId = legalUnitRegId,
                Persons = CreatePersons()
            }, DbContextExtensions.UserId);
        }

        public async Task EditEnterpriseUnitAsync(NSCRegDbContext context, List<ActivityM> activities,
            int[] legalUnitsIds, int unitId, string unitNameEdit, int? enterpriseGroupId)
        {
            await new EditService(context, _analysisRules, _mandatoryFields).EditEnterpriseUnit(new EnterpriseUnitEditM
            {
                RegId = unitId,
                Name = unitNameEdit,
                LegalUnits = legalUnitsIds,
                DataAccess = DbContextExtensions.DataAccessEnterpriseUnit,
                Address = await CreateAddressAsync(context),
                Activities = activities,
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = nameof(LegalUnitCreateM.ContactPerson),
                ShortName = nameof(LegalUnitCreateM.ShortName),
                TelephoneNo = nameof(LegalUnitCreateM.TelephoneNo),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                Status = StatUnitStatuses.Active,
                EntGroupId = enterpriseGroupId,
                Persons = CreatePersons()
            }, DbContextExtensions.UserId);
        }

        public async Task EditEnterpriseGroupAsync(NSCRegDbContext context, int unitId, string unitNameEdit,
            int[] enterpriseUnitsIds, int[] legalUnitsIds)
        {
            await new EditService(context, _analysisRules, _mandatoryFields).EditEnterpriseGroup(new EnterpriseGroupEditM
            {
                RegId = unitId,
                Name = unitNameEdit,
                EnterpriseUnits = enterpriseUnitsIds,
                DataAccess = DbContextExtensions.DataAccessEnterpriseGroup,
                Address = await CreateAddressAsync(context),
                DataSource = nameof(LegalUnitCreateM.DataSource),
                ContactPerson = nameof(LegalUnitCreateM.ContactPerson),
                ShortName = nameof(LegalUnitCreateM.ShortName),
                TelephoneNo = nameof(LegalUnitCreateM.TelephoneNo),
                RegistrationReason = nameof(LegalUnitCreateM.RegistrationReason),
                LegalUnits = legalUnitsIds
            }, DbContextExtensions.UserId);
        }

    }
}
