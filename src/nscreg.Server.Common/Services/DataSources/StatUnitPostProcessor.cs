using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;
using Activity = nscreg.Data.Entities.Activity;

namespace nscreg.Server.Common.Services.DataSources
{
    internal class StatUnitPostProcessor
    {
        private readonly Dictionary<DataSourceUploadTypes, Func<StatisticalUnit, Task<string>>> _postActionsMap;
        private readonly NSCRegDbContext _ctx;

        public StatUnitPostProcessor(NSCRegDbContext ctx)
        {
            _ctx = ctx;
            _postActionsMap = new Dictionary<DataSourceUploadTypes, Func<StatisticalUnit, Task<string>>>()
            {
                [DataSourceUploadTypes.Activities] = PostProcessActivitiesUpload,
                [DataSourceUploadTypes.StatUnits] = PostProcessStatUnitsUpload
            };

        }

        public async Task<string> FillIncompleteDataOfStatUnit(StatisticalUnit unit, DataSourceUploadTypes uploadType)
        {
            var errorText =  await _postActionsMap[uploadType](unit);
            return errorText;
        }

        private async Task<string> PostProcessActivitiesUpload(StatisticalUnit unit)
        {
            if (!unit.Activities?.Any(activity => activity.Id == 0) == true)
                return string.Empty;
            foreach (var activityUnit in unit.ActivitiesUnits)
            {
                if (activityUnit.Activity.Id != 0)
                    continue;
                var filled = await TryGetFilledActivityAsync(activityUnit.Activity);
                activityUnit.Activity = Mapper.Map(activityUnit.Activity, filled);
            }

            async Task<Activity> TryGetFilledActivityAsync(Activity activity)
            {
                if(activity.ActivityCategory == null) throw new Exception("Activity category by selected code not found");
                var domainActivity = await _ctx.Activities
                    .Include(a => a.ActivityCategory)
                    .FirstOrDefaultAsync(a => a.ActivitiesUnits.Any(x => x.UnitId == unit.RegId)
                                              && a.ActivityCategory.Code == activity.ActivityCategory.Code);
                if (domainActivity != null) return domainActivity;
                activity.ActivityCategory =
                    await _ctx.ActivityCategories.FirstOrDefaultAsync(x => x.Code == activity.ActivityCategory.Code);
                return activity;
            }
            return string.Empty;
        }

        private async Task<string> PostProcessStatUnitsUpload(StatisticalUnit unit)
        {
            List<string> errors = new List<string>();
            try
            {
                /// TODO: May be removed since activities are already included by <see cref="PopulateService.GetStatUnitBase(IReadOnlyDictionary{string, object})"/> 
                await unit.ActivitiesUnits?.Where(activityUnit => activityUnit.Activity.Id == 0)
                    .ForEachAsync(async au =>
                    {
                        try
                        {
                            au.Activity = await GetFilledActivity(au.Activity);
                        }
                        catch (Exception ex)
                        {
                            errors.Add(ex.Message);
                        }
                    });

                /// TODO: May be removed (all 3 types of addresses) since address is already included by <see cref="PopulateService.GetStatUnitBase(IReadOnlyDictionary{string, object})"/>. But before need to check, how property <see cref="Address.Region"/> is resolved after mapping
                if (unit.Address?.Id == 0)
                    unit.Address = await GetFilledAddress(unit.Address);

                if (unit.PostalAddress?.Id == 0)
                    unit.PostalAddress = await GetFilledAddress(unit.PostalAddress);

                if (unit.ActualAddress?.Id == 0)
                    unit.ActualAddress = await GetFilledAddress(unit.ActualAddress);

                /// TODO: Maybe it should be placed in <see cref="nscreg.Business.DataSources.StatUnitKeyValueParser.ParseAndMutateStatUnit(IReadOnlyDictionary{string, object}, StatisticalUnit)"/>
                await unit.ForeignParticipationCountriesUnits?.Where(fpcu => fpcu.Id == 0).ForEachAsync(async fpcu =>
                    {
                        try
                        {
                            var country = await GetFilledCountry(fpcu.Country);
                            fpcu.Country = country;
                            fpcu.CountryId = country.Id;
                            fpcu.UnitId = unit.RegId;
                        }
                        catch (Exception ex)
                        {
                            errors.Add(ex.Message);
                        }
                    });

                // Todo: languageName1 and languageName2 is not checked
                if (unit.ForeignParticipation?.Id == 0)
                {
                    var fp = await GetFilledForeignParticipation(unit.ForeignParticipation);
                    unit.ForeignParticipation = fp;
                    unit.ForeignParticipationId = fp.Id;
                }

                if (!string.IsNullOrEmpty(unit.LegalForm?.Name) || !string.IsNullOrEmpty(unit.LegalForm?.Code))
                {
                    unit.LegalForm = await GetFilledLegalForm(unit.LegalForm);
                }

                if (unit.LegalForm != null)
                    unit.LegalFormId = unit.LegalForm?.Id;

                // TODO: It can attach Person with the same name as other person, if other fields are not filled
                await unit.PersonsUnits?.Where(personUnit => personUnit.PersonId == null)
                    .ForEachAsync(async per =>
                    {
                        try
                        {
                            per.Person = await GetFilledPerson(per.Person);
                        }
                        catch (Exception ex)
                        {
                            errors.Add(ex.Message);
                        }
                    });

                switch (unit)
                {
                    case LocalUnit localUnit:
                        if (localUnit.LegalUnitId != null && localUnit.LegalUnitId != 0)
                        {
                            var linkedLegalUnit = await GetLegalUnitId(localUnit.LegalUnitId.ToString());
                            localUnit.LegalUnitId = linkedLegalUnit?.RegId;
                        }
                        break;

                    case LegalUnit legalUnit:
                        if (legalUnit.EnterpriseUnitRegId != null && legalUnit.EnterpriseUnitRegId != 0)
                        {
                            var linkedEnterpriseUnit = await GetEnterpriseUnitRegId(legalUnit.EnterpriseUnitRegId.ToString());
                            legalUnit.EnterpriseUnitRegId = linkedEnterpriseUnit?.RegId;
                        }
                        break;

                    case EnterpriseUnit enterpriseUnit:
                        if (enterpriseUnit.EntGroupId != null && enterpriseUnit.EntGroupId != 0)
                        {
                            var enterpriseGroup = await GetEnterpriseGroupId(enterpriseUnit.EntGroupId.ToString());
                            enterpriseUnit.EntGroupId = enterpriseGroup?.RegId;
                        }
                        break;
                }

                // Todo: search on table, which doesnt have indexes for these search parameters.
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
                ex.Data.Add("unit", unit);
                throw;
            }

            return string.Join(". ", errors);
        }

        private async Task<Activity> GetFilledActivity(Activity parsedActivity)
        {
            if (parsedActivity.ActivityCategory == null)
                throw new Exception("Activity category by mapping code not found");
            var activityCategory = _ctx.ActivityCategories.FirstOrDefault(ac =>
                !ac.IsDeleted
                && (parsedActivity.ActivityCategory.Code.HasValue()
                    && parsedActivity.ActivityCategory.Code == ac.Code
                    || parsedActivity.ActivityCategory.Name.HasValue()
                    && parsedActivity.ActivityCategory.Name == ac.Name))
                    ?? throw new Exception($"Activity category by: {parsedActivity.ActivityCategory.Code} code or {parsedActivity.ActivityCategory.Name} name not found");

            parsedActivity.ActivityCategory = activityCategory;
            parsedActivity.ActivityCategoryId = activityCategory.Id;
            // TODO: rewrite search. The of activity is statId + ActivityCategory.Code + Year
            // Also, this return of dbEntity instead of parsed make us to loose 3 fields from parsed (Year, Turnover, Employees)
            // We need to map fields from parsed
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
            var code = parsedAddress.Region?.Code;
            var name = parsedAddress.Region?.Name;

            var region = _ctx.Regions.FirstOrDefault(reg => !reg.IsDeleted
                && (code.HasValue()
                    && code == reg.Code
                    || name.HasValue()
                    && name == reg.Name))
                    ?? throw new Exception($"Address Region: `{code}` code or `{name}` name not found");

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
            if (parsedPerson.NationalityCode?.Code != null && parsedPerson.NationalityCode?.Name != null)
            {
                var country = _ctx.Countries.FirstOrDefault(c => !c.IsDeleted
                                                                 && (parsedPerson.NationalityCode.Code.HasValue()
                                                                     && c.Code == parsedPerson.NationalityCode.Code
                                                                     || parsedPerson.NationalityCode.Name.HasValue()
                                                                     && c.Name == parsedPerson.NationalityCode.Name))
                              ?? throw new Exception($"Person Nationality Code by `{parsedPerson.NationalityCode.Code}` code or `{parsedPerson.NationalityCode.Name}` name not found");
                parsedPerson.CountryId = country.Id;
            }
            return await _ctx.Persons
                           .Include(p => p.NationalityCode)
                           .FirstOrDefaultAsync(p =>
                               (string.IsNullOrWhiteSpace(parsedPerson.GivenName) ||
                                p.GivenName == parsedPerson.GivenName)
                               && (string.IsNullOrWhiteSpace(parsedPerson.Surname) || p.Surname == parsedPerson.Surname)
                               && (string.IsNullOrWhiteSpace(parsedPerson.PersonalId) ||
                                   p.PersonalId == parsedPerson.PersonalId)
                               && (!parsedPerson.BirthDate.HasValue || p.BirthDate == parsedPerson.BirthDate)) ??
                       parsedPerson;
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
