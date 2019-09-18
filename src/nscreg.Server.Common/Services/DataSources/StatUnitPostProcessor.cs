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

                if (unit.ForeignParticipationCountriesUnits?.Any(fpcu => fpcu.Id == 0) == true)
                    await unit.ForeignParticipationCountriesUnits.ForEachAsync(async fpcu =>
                    {
                        if (fpcu.Country.Id == 0)
                        {
                            var country =  await GetFilledCountry(fpcu.Country);
                            fpcu.Country = country;
                            fpcu.CountryId = country.Id;
                            fpcu.UnitId = unit.RegId;
                        }
                    });

                if (unit.ForeignParticipation?.Id == 0)
                {
                    var fp = await GetFilledForeignParticipation(unit.ForeignParticipation);
                    unit.ForeignParticipation = fp;
                    unit.ForeignParticipationId = fp.Id;
                }

                if (!string.IsNullOrEmpty(unit.LegalForm?.Name) || !string.IsNullOrEmpty(unit.LegalForm?.Code))
                {
                    unit.LegalForm = await GetFilledLegalForm(unit.LegalForm);
                    unit.LegalFormId = unit.LegalForm?.Id;
                }

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

                if (!string.IsNullOrEmpty(unit.DataSourceClassification?.Name) || !string.IsNullOrEmpty(unit.DataSourceClassification?.Code))
                {
                    unit.DataSourceClassification = await GetFilledDataSourceClassification(unit.DataSourceClassification);
                    unit.DataSourceClassificationId = unit.DataSourceClassification?.Id;
                }

                if (!string.IsNullOrEmpty(unit.InstSectorCode?.Name) || !string.IsNullOrEmpty(unit.InstSectorCode?.Code))
                {
                    unit.InstSectorCode = await GetFilledSectorCode(unit.InstSectorCode);
                    unit.InstSectorCodeId = unit.InstSectorCode?.Id;
                }

                if (!string.IsNullOrEmpty(unit.Size?.Name))
                {
                    unit.Size = await GetFilledSize(unit.Size);
                    unit.SizeId = unit.Size?.Id;
                }

                if (!string.IsNullOrEmpty(unit.UnitStatus?.Name) || !string.IsNullOrEmpty(unit.UnitStatus?.Code))
                {
                    unit.UnitStatus = await GetFilledUnitStatus(unit.UnitStatus);
                    unit.UnitStatusId = unit.UnitStatus?.Id;
                }

                if (!string.IsNullOrEmpty(unit.ReorgType?.Name) || !string.IsNullOrEmpty(unit.ReorgType?.Code))
                {
                    unit.ReorgType = await GetFilledReorgType(unit.ReorgType);
                    unit.ReorgTypeId = unit.ReorgType?.Id;
                }

                if (!string.IsNullOrEmpty(unit.RegistrationReason?.Name) || !string.IsNullOrEmpty(unit.RegistrationReason?.Code))
                {
                    unit.RegistrationReason = await GetFilledRegistrationReason(unit.RegistrationReason);
                    unit.RegistrationReasonId = unit.RegistrationReason?.Id;
                }
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

        private async Task<ForeignParticipation> GetFilledForeignParticipation(ForeignParticipation foreignParticipation)
        {
            return await _ctx.ForeignParticipations.FirstOrDefaultAsync(c =>
                       !c.IsDeleted
                       && (string.IsNullOrWhiteSpace(foreignParticipation.Code) || c.Code == foreignParticipation.Code)
                       && (string.IsNullOrWhiteSpace(foreignParticipation.Name) || c.Name == foreignParticipation.Name))
                   ?? throw new Exception($"Country by `{foreignParticipation.Code}` code or `{foreignParticipation.Name}` name not found");
        }

        private async Task<LegalForm> GetFilledLegalForm(LegalForm parsedLegalForm)
        {
            LegalForm lf = null;
            if (!string.IsNullOrEmpty(parsedLegalForm.Name) && !string.IsNullOrEmpty(parsedLegalForm.Code))
            {
                lf = await _ctx.LegalForms.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == parsedLegalForm.Name || dsc.NameLanguage1 == parsedLegalForm.Name || dsc.NameLanguage2 == parsedLegalForm.Name) &&
                    dsc.Code == parsedLegalForm.Code);
            }
            else if (!string.IsNullOrEmpty(parsedLegalForm.Name))
            {
                lf = await _ctx.LegalForms.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == parsedLegalForm.Name || dsc.NameLanguage1 == parsedLegalForm.Name || dsc.NameLanguage2 == parsedLegalForm.Name));
            }
            else if (!string.IsNullOrEmpty(parsedLegalForm.Code))
            {
                lf = await _ctx.LegalForms.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && dsc.Code == parsedLegalForm.Code);
            }

            if (lf == null)
            {
                throw new Exception($"Legal form by `{parsedLegalForm.Name}` name and {parsedLegalForm.Code} code not found");
            }

            return lf;
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
            DataSourceClassification ds = null;
            if (!string.IsNullOrEmpty(parseDataSourceClassification.Name) && !string.IsNullOrEmpty(parseDataSourceClassification.Code))
            {
                ds = await _ctx.DataSourceClassifications.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == parseDataSourceClassification.Name || dsc.NameLanguage1 == parseDataSourceClassification.Name || dsc.NameLanguage2 == parseDataSourceClassification.Name) &&
                    dsc.Code == parseDataSourceClassification.Code);
            }else if (!string.IsNullOrEmpty(parseDataSourceClassification.Name))
            {
                ds = await _ctx.DataSourceClassifications.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == parseDataSourceClassification.Name || dsc.NameLanguage1 == parseDataSourceClassification.Name || dsc.NameLanguage2 == parseDataSourceClassification.Name));
            }
            else if (!string.IsNullOrEmpty(parseDataSourceClassification.Code))
            {
                ds = await _ctx.DataSourceClassifications.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && dsc.Code == parseDataSourceClassification.Code);
            }

            if(ds == null)
            {
                throw new Exception($"Data source classification by `{parseDataSourceClassification.Name}` name and {parseDataSourceClassification.Code} code not found");
            }

            return ds;
        }

        private async Task<UnitSize> GetFilledSize(UnitSize size)
        {
            return await _ctx.UnitsSize.FirstOrDefaultAsync(s =>
                !s.IsDeleted && (s.Name == size.Name || s.NameLanguage1 == size.Name || s.NameLanguage2 == size.Name))
                   ?? throw new Exception($"Size with {size.Name} name wasn't found");
        }

        private async Task<UnitStatus> GetFilledUnitStatus(UnitStatus unitStatus)
        {
            UnitStatus us = null;
            if (!string.IsNullOrEmpty(unitStatus.Name) && !string.IsNullOrEmpty(unitStatus.Code))
            {
                us = await _ctx.Statuses.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == unitStatus.Name || dsc.NameLanguage1 == unitStatus.Name || dsc.NameLanguage2 == unitStatus.Name) &&
                    dsc.Code == unitStatus.Code);
            }
            else if (!string.IsNullOrEmpty(unitStatus.Name))
            {
                us = await _ctx.Statuses.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == unitStatus.Name || dsc.NameLanguage1 == unitStatus.Name || dsc.NameLanguage2 == unitStatus.Name));
            }
            else if (!string.IsNullOrEmpty(unitStatus.Code))
            {
                us = await _ctx.Statuses.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && dsc.Code == unitStatus.Code);
            }

            if (us == null)
            {
                throw new Exception($"Unit status by `{unitStatus.Name}` name and {unitStatus.Code} code not found");
            }

            return us;
        }

        private async Task<ReorgType> GetFilledReorgType(ReorgType reorgType)
        {
            ReorgType rt = null;
            if (!string.IsNullOrEmpty(reorgType.Name) && !string.IsNullOrEmpty(reorgType.Code))
            {
                rt = await _ctx.ReorgTypes.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == reorgType.Name || dsc.NameLanguage1 == reorgType.Name || dsc.NameLanguage2 == reorgType.Name) &&
                    dsc.Code == reorgType.Code);
            }
            else if (!string.IsNullOrEmpty(reorgType.Name))
            {
                rt = await _ctx.ReorgTypes.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == reorgType.Name || dsc.NameLanguage1 == reorgType.Name || dsc.NameLanguage2 == reorgType.Name));
            }
            else if (!string.IsNullOrEmpty(reorgType.Code))
            {
                rt = await _ctx.ReorgTypes.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && dsc.Code == reorgType.Code);
            }

            if (rt == null)
            {
                throw new Exception($"Reorg type by `{reorgType.Name}` name and {reorgType.Code} code not found");
            }

            return rt;
        }

        private async Task<RegistrationReason> GetFilledRegistrationReason(RegistrationReason registrationReason)
        {
            RegistrationReason rr = null;
            if (!string.IsNullOrEmpty(registrationReason.Name) && !string.IsNullOrEmpty(registrationReason.Code))
            {
                rr = await _ctx.RegistrationReasons.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == registrationReason.Name || dsc.NameLanguage1 == registrationReason.Name || dsc.NameLanguage2 == registrationReason.Name) &&
                    dsc.Code == registrationReason.Code);
            }
            else if (!string.IsNullOrEmpty(registrationReason.Name))
            {
                rr = await _ctx.RegistrationReasons.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && (dsc.Name == registrationReason.Name || dsc.NameLanguage1 == registrationReason.Name || dsc.NameLanguage2 == registrationReason.Name));
            }
            else if (!string.IsNullOrEmpty(registrationReason.Code))
            {
                rr = await _ctx.RegistrationReasons.FirstOrDefaultAsync(dsc =>
                    !dsc.IsDeleted && dsc.Code == registrationReason.Code);
            }

            if (rr == null)
            {
                throw new Exception($"Registration reason by `{registrationReason.Name}` name and {registrationReason.Code} code not found");
            }

            return rr;
        }

        private async Task<StatisticalUnit> GetLegalUnitId(string legalUnitStatId)
        {
            return await _ctx.LegalUnits.FirstOrDefaultAsync(legU =>
                !legU.IsDeleted
                && legalUnitStatId.HasValue()
                && (legU.StatId == legalUnitStatId
                    || legU.RegId == int.Parse(legalUnitStatId)))
                ?? throw new Exception($"Legal unit by: `{legalUnitStatId}` not found");
        }

        private async Task<StatisticalUnit> GetEnterpriseUnitRegId(string enterpriseUnitStatId)
        {
            return await _ctx.EnterpriseUnits.FirstOrDefaultAsync(en =>
                !en.IsDeleted
                && enterpriseUnitStatId.HasValue()
                && (en.StatId == enterpriseUnitStatId
                    || en.RegId == int.Parse(enterpriseUnitStatId)))
                ?? throw new Exception($"Enterprise unit by: `{enterpriseUnitStatId}` not found");
        }

        private async Task<EnterpriseGroup> GetEnterpriseGroupId(string enterpriseGroupStatId)
        {
            return await _ctx.EnterpriseGroups.FirstOrDefaultAsync(eng =>
                !eng.IsDeleted
                && enterpriseGroupStatId.HasValue()
                && (eng.StatId == enterpriseGroupStatId
                    || eng.RegId == int.Parse(enterpriseGroupStatId)))
                ?? throw new Exception($"Enterprise group by: `{enterpriseGroupStatId}` not found");
        }
    }
}
