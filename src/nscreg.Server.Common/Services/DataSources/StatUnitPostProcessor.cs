using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    internal class StatUnitPostProcessor
    {
        private readonly Dictionary<DataSourceUploadTypes, Func<StatisticalUnit, Task>> _postActionsMap;
        private readonly NSCRegDbContext _ctx;

        public StatUnitPostProcessor(NSCRegDbContext ctx)
        {
            _ctx = ctx;
            _postActionsMap = new Dictionary<DataSourceUploadTypes, Func<StatisticalUnit, Task>>()
            {
                [DataSourceUploadTypes.Activities] = PostProcessActivitiesUpload,
                [DataSourceUploadTypes.StatUnits] = PostProcessStatUnitsUpload
            };

        }

        public async Task FillIncompleteDataOfStatUnit(StatisticalUnit unit, DataSourceUploadTypes uploadType)
        {
            await _postActionsMap[uploadType](unit);
        }

        private async Task PostProcessActivitiesUpload(StatisticalUnit unit)
        {
            if (!unit.Activities?.Any(activity => activity.Id == 0) == true)
                return;

            foreach (var activityUnit in unit.ActivitiesUnits)
            {
                if (activityUnit.Activity.Id != 0)
                    continue;
                var filled = await TryGetFilledActivityAsync(activityUnit.Activity);
                activityUnit.Activity = Mapper.Map(activityUnit.Activity, filled);
            }

            async Task<Activity> TryGetFilledActivityAsync(Activity activity)
            {
                var domainActivity = await _ctx.Activities
                    .Include(a => a.ActivityCategory)
                    .FirstOrDefaultAsync(a => a.ActivitiesUnits.Any(x => x.UnitId == unit.RegId)
                                              && a.ActivityCategory.Code == activity.ActivityCategory.Code);
                if (domainActivity != null) return domainActivity;

                activity.ActivityCategory =
                    await _ctx.ActivityCategories.FirstAsync(x => x.Code == activity.ActivityCategory.Code);
                return activity;
            }

        }

        

        private async Task PostProcessStatUnitsUpload(StatisticalUnit unit)
        {
            try
            {
                if (unit.Activities?.Any(activity => activity.Id == 0) == true)
                    await unit.ActivitiesUnits
                        .ForEachAsync(async au =>
                        {
                            if (au.Activity.Id == 0)
                                au.Activity = await GetFilledActivity(au.Activity);
                        });

                if (unit.Address?.Id == 0)
                    unit.Address = await GetFilledAddress(unit.Address);

                if (unit.ForeignParticipationCountry?.Id == 0)
                    unit.ForeignParticipationCountry = await GetFilledCountry(unit.ForeignParticipationCountry);

                if (unit.LegalForm?.Id == 0)
                    unit.LegalForm = await GetFilledLegalForm(unit.LegalForm);

                if (unit.LegalForm != null)
                    unit.LegalFormId = unit.LegalForm?.Id;

                if (unit.Persons?.Any(person => person.Id == 0) == true)
                    await unit.PersonsUnits.ForEachAsync(async pu =>
                    {
                        if (pu.Person.Id == 0)
                            pu.Person = await GetFilledPerson(pu.Person);
                    });

                if (unit.UnitType == StatUnitTypes.LocalUnit)
                {
                    var res = unit as LocalUnit;
                    if (res?.LegalUnitId != null && res.LegalUnitId != 0)
                    {
                        var legalUnit = await GetLegalUnitId(res.LegalUnitId.ToString());
                        res.LegalUnitId = legalUnit?.RegId;
                        unit = res;
                    }
                }

                if (unit.UnitType == StatUnitTypes.LegalUnit)
                {
                    var res = unit as LegalUnit;
                    if (res?.EnterpriseUnitRegId != null && res.EnterpriseUnitRegId != 0)
                    {
                        var enterpriseUnit = await GetEnterpriseUnitRegId(res.EnterpriseUnitRegId.ToString());
                        res.EnterpriseUnitRegId = enterpriseUnit?.RegId;
                        unit = res;
                    }
                }

                if (unit.UnitType == StatUnitTypes.EnterpriseUnit)
                {
                    var res = unit as EnterpriseUnit;
                    if (res?.EntGroupId != null && res.EntGroupId != 0)
                    {
                        var enterpriseGroup = await GetEnterpriseGroupId(res.EntGroupId.ToString());
                        res.EntGroupId = enterpriseGroup?.RegId;
                        unit = res;
                    }
                }

                if (unit.DataSourceClassification?.Name != null)
                {
                    unit.DataSourceClassification = await GetFilledDataSourceClassification(unit.DataSourceClassification);
                    unit.DataSourceClassificationId = unit.DataSourceClassification?.Id;
                }

                if (unit.InstSectorCode?.Id == 0)
                    unit.InstSectorCode = await GetFilledSectorCode(unit.InstSectorCode);
            }
            catch (Exception ex)
            {
                ex.Data.Add("Postprocess exceptions at: ", unit);
                throw;
            }
        }

        private async Task<Activity> GetFilledActivity(Activity parsedActivity)
        {
            var activityCategory = _ctx.ActivityCategories.FirstOrDefault(ac =>
                !ac.IsDeleted
                && (parsedActivity.ActivityCategory.Code.HasValue()
                    && parsedActivity.ActivityCategory.Code == ac.Code
                    || parsedActivity.ActivityCategory.Name.HasValue()
                    && parsedActivity.ActivityCategory.Name == ac.Name))
                    ?? throw new Exception($"Activity category by: `{parsedActivity.ActivityCategory.Code}` code or `{parsedActivity.ActivityCategory.Name}` name not found");

            parsedActivity.ActivityCategory = activityCategory;
            parsedActivity.ActivityCategoryId = activityCategory.Id;

            return await _ctx.Activities
                       .Include(a => a.ActivityCategory)
                       .FirstOrDefaultAsync(a =>
                           a.ActivityCategory != null
                           && !a.ActivityCategory.IsDeleted
                           && (parsedActivity.ActivityType == 0 || a.ActivityType == parsedActivity.ActivityType)
                           && (parsedActivity.ActivityCategoryId == 0 ||
                               a.ActivityCategoryId == parsedActivity.ActivityCategoryId)
                           && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Code) ||
                               a.ActivityCategory.Code == parsedActivity.ActivityCategory.Code)
                           && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Name) ||
                               a.ActivityCategory.Name == parsedActivity.ActivityCategory.Name)
                           && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Section) ||
                               a.ActivityCategory.Section == parsedActivity.ActivityCategory.Section))
                   ?? parsedActivity;
        }

        private async Task<Address> GetFilledAddress(Address parsedAddress)
        {
            var region = _ctx.Regions.FirstOrDefault(reg => !reg.IsDeleted
                && (parsedAddress.Region.Code.HasValue()
                    && parsedAddress.Region.Code == reg.Code
                    || parsedAddress.Region.Name.HasValue()
                    && parsedAddress.Region.Name == reg.Name))
                    ?? throw new Exception($"Address Region: `{parsedAddress.Region.Code}` code or `{parsedAddress.Region.Name}` name not found");

            parsedAddress.RegionId = region.Id;

            return await _ctx.Address
                       .Include(a => a.Region)
                       .FirstOrDefaultAsync(a =>
                           a.Region != null
                           && !a.Region.IsDeleted
                           && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart1) ||
                               a.AddressPart1 == parsedAddress.AddressPart1)
                           && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart2) ||
                               a.AddressPart2 == parsedAddress.AddressPart2)
                           && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart3) ||
                               a.AddressPart3 == parsedAddress.AddressPart3)
                           && (!parsedAddress.Latitude.HasValue ||
                               a.Latitude == parsedAddress.Latitude)
                           && (!parsedAddress.Longitude.HasValue ||
                               a.Longitude == parsedAddress.Longitude)
                           && (string.IsNullOrWhiteSpace(parsedAddress.Region.Name) ||
                               a.Region.Name == parsedAddress.Region.Name)
                           && (string.IsNullOrWhiteSpace(parsedAddress.Region.Code) ||
                               a.Region.Code == parsedAddress.Region.Code)
                           && (string.IsNullOrWhiteSpace(parsedAddress.Region.AdminstrativeCenter) ||
                               a.Region.AdminstrativeCenter == parsedAddress.Region.AdminstrativeCenter))
                   ?? parsedAddress;
        }

        private async Task<Country> GetFilledCountry(Country parsedCountry)
        {
            return await _ctx.Countries.FirstOrDefaultAsync(c =>
                       !c.IsDeleted
                       && (string.IsNullOrWhiteSpace(parsedCountry.Code) || c.Code == parsedCountry.Code)
                       && (string.IsNullOrWhiteSpace(parsedCountry.Name) || c.Name == parsedCountry.Name))
                       ?? throw new Exception($"Country by `{parsedCountry.Code}` code or `{parsedCountry.Name}` name not found");
        }

        private async Task<LegalForm> GetFilledLegalForm(LegalForm parsedLegalForm)
        {
            return await _ctx.LegalForms.FirstOrDefaultAsync(lf =>
                       !lf.IsDeleted
                       && (string.IsNullOrWhiteSpace(parsedLegalForm.Code) || lf.Code == parsedLegalForm.Code)
                       && (string.IsNullOrWhiteSpace(parsedLegalForm.Name) || lf.Name == parsedLegalForm.Name))
                       ?? throw new Exception($"Legal form by `{parsedLegalForm.Code}` code or `{parsedLegalForm.Name}` name not found");
        }

        private async Task<Person> GetFilledPerson(Person parsedPerson)
        {
            var country = _ctx.Countries.FirstOrDefault(c => !c.IsDeleted
                && (parsedPerson.NationalityCode.Code.HasValue()
                    && c.Code == parsedPerson.NationalityCode.Code
                    || parsedPerson.NationalityCode.Name.HasValue()
                    && c.Name == parsedPerson.NationalityCode.Name))
                    ?? throw new Exception($"Person Nationality Code by `{parsedPerson.NationalityCode.Code}` code or `{parsedPerson.NationalityCode.Name}` name not found");

            parsedPerson.CountryId = country.Id;

            return await _ctx.Persons
                       .Include(p => p.NationalityCode)
                       .FirstOrDefaultAsync(p =>
                           (string.IsNullOrWhiteSpace(parsedPerson.GivenName) || p.GivenName == parsedPerson.GivenName)
                           && (string.IsNullOrWhiteSpace(parsedPerson.Surname) || p.Surname == parsedPerson.Surname)
                           && (string.IsNullOrWhiteSpace(parsedPerson.PersonalId) ||
                               p.PersonalId == parsedPerson.PersonalId)
                           && (!parsedPerson.BirthDate.HasValue || p.BirthDate == parsedPerson.BirthDate))
                   ?? parsedPerson;
        }

        private async Task<SectorCode> GetFilledSectorCode(SectorCode parsedSectorCode)
        {
            return await _ctx.SectorCodes.FirstOrDefaultAsync(sc =>
                       !sc.IsDeleted
                       && (string.IsNullOrWhiteSpace(parsedSectorCode.Code) || sc.Code == parsedSectorCode.Code)
                       && (string.IsNullOrWhiteSpace(parsedSectorCode.Name) || sc.Name == parsedSectorCode.Name))
                       ?? throw new Exception($"Sector code by `{parsedSectorCode.Code}` code or `{parsedSectorCode.Name}` name not found");
        }

        private async Task<DataSourceClassification> GetFilledDataSourceClassification(DataSourceClassification parseDataSourceClassification)
        {
            return await _ctx.DataSourceClassifications.FirstOrDefaultAsync(dsc => !dsc.IsDeleted && dsc.Name == parseDataSourceClassification.Name)
                ?? throw new Exception($"Data source classification by `{parseDataSourceClassification.Name}` name not found");
        }

        private async Task<StatisticalUnit> GetLegalUnitId(string legalUnitStatId)
        {
            return await _ctx.LegalUnits.FirstOrDefaultAsync(legU =>
                !legU.IsDeleted
                && legalUnitStatId.HasValue()
                && legU.ParentId == null
                && (legU.StatId == legalUnitStatId
                    || legU.RegId == int.Parse(legalUnitStatId)))
                ?? throw new Exception($"Legal unit by: `{legalUnitStatId}` not found");
        }

        private async Task<StatisticalUnit> GetEnterpriseUnitRegId(string enterpriseUnitStatId)
        {
            return await _ctx.EnterpriseUnits.FirstOrDefaultAsync(en =>
                !en.IsDeleted
                && enterpriseUnitStatId.HasValue()
                && en.ParentId == null
                && (en.StatId == enterpriseUnitStatId
                    || en.RegId == int.Parse(enterpriseUnitStatId)))
                ?? throw new Exception($"Enterprise unit by: `{enterpriseUnitStatId}` not found");
        }

        private async Task<EnterpriseGroup> GetEnterpriseGroupId(string enterpriseGroupStatId)
        {
            return await _ctx.EnterpriseGroups.FirstOrDefaultAsync(eng =>
                !eng.IsDeleted
                && enterpriseGroupStatId.HasValue()
                && eng.ParentId == null
                && (eng.StatId == enterpriseGroupStatId
                    || eng.RegId == int.Parse(enterpriseGroupStatId)))
                ?? throw new Exception($"Enterprise group by: `{enterpriseGroupStatId}` not found");
        }
    }
}
