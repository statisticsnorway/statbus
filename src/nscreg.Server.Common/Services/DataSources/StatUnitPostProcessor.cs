using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    public class StatUnitPostProcessor
    {
        private readonly NSCRegDbContext _ctx;
        public StatUnitPostProcessor(NSCRegDbContext ctx)
        {
            _ctx = ctx;

        }
        public async Task<string> PostProcessStatUnitsUpload(StatisticalUnit unit)
        {
            List<string> errors = new List<string>();
            void Try(Action action)
            {
                try
                {
                    action.Invoke();
                }
                catch (Exception ex)
                {
                    errors.Add(ex.Message);
                }
            }
            try
            {

                unit.ActivitiesUnits?
                    .Where(activityUnit => activityUnit.Activity.Id == 0)
                    .ForEach(au => Try(() =>
                        au.Activity = GetFilledActivity(au.Activity)
                    ));

                if (unit.PostalAddress?.Id == 0)
                    Try(() => unit.PostalAddress = GetFilledAddress(unit.PostalAddress));

                if (unit.ActualAddress?.Id == 0)
                    Try(() => unit.ActualAddress = GetFilledAddress(unit.ActualAddress));

                unit.ForeignParticipationCountriesUnits?
                    .Where(fpcu => fpcu.Id == 0).ForEach(fpcu =>
                        Try(() =>
                        {
                            var country = GetFilledCountry(fpcu.Country);
                            fpcu.Country = country;
                            fpcu.CountryId = country.Id;
                            fpcu.UnitId = unit.RegId;
                        })
                    );

                if (unit.ForeignParticipation?.Id == 0)
                {
                    var fp = GetFilledForeignParticipation(unit.ForeignParticipation);
                    unit.ForeignParticipation = fp;
                    unit.ForeignParticipationId = fp.Id;
                }

                if (!string.IsNullOrEmpty(unit.LegalForm?.Name) || !string.IsNullOrEmpty(unit.LegalForm?.Code))
                {
                    unit.LegalForm = GetFilledLegalForm(unit.LegalForm);
                }

                if (unit.LegalForm != null)
                    unit.LegalFormId = unit.LegalForm?.Id;

                // TODO: It can attach Person with the same name as other person, if other fields are not filled
                unit.PersonsUnits?
                    .Where(personUnit => personUnit.PersonId == null)
                    .ForEach(per => Try(() =>
                        per.Person = GetFilledPerson(per.Person)
                    ));

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
                    unit.DataSourceClassification = GetFilledDataSourceClassification(unit.DataSourceClassification);
                    unit.DataSourceClassificationId = unit.DataSourceClassification?.Id;
                }

                if (!string.IsNullOrEmpty(unit.InstSectorCode?.Name) || !string.IsNullOrEmpty(unit.InstSectorCode?.Code))
                {
                    unit.InstSectorCode = GetFilledSectorCode(unit.InstSectorCode);
                    unit.InstSectorCodeId = unit.InstSectorCode?.Id;
                }

                if (!string.IsNullOrEmpty(unit.Size?.Name))
                {
                    unit.Size = GetFilledSize(unit.Size);
                    unit.SizeId = unit.Size?.Id;
                }

                if (!string.IsNullOrEmpty(unit.UnitStatus?.Name) || !string.IsNullOrEmpty(unit.UnitStatus?.Code))
                {
                    unit.UnitStatus = GetFilledUnitStatus(unit.UnitStatus);
                    unit.UnitStatusId = unit.UnitStatus?.Id;
                }

                if (!string.IsNullOrEmpty(unit.ReorgType?.Name) || !string.IsNullOrEmpty(unit.ReorgType?.Code))
                {
                    unit.ReorgType = GetFilledReorgType(unit.ReorgType);
                    unit.ReorgTypeId = unit.ReorgType?.Id;
                }

                if (!string.IsNullOrEmpty(unit.RegistrationReason?.Name) || !string.IsNullOrEmpty(unit.RegistrationReason?.Code))
                {
                    unit.RegistrationReason = GetFilledRegistrationReason(unit.RegistrationReason);
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

        private Activity GetFilledActivity(Activity parsedActivity)
        {
            if (parsedActivity.ActivityCategory != null && (parsedActivity.ActivityCategory.Code.HasValue() || parsedActivity.ActivityCategory.Name.HasValue()))
            {
                var activityCategory = _ctx.ActivityCategories.AsNoTracking().FirstOrDefault(ac => !ac.IsDeleted && (!string.IsNullOrEmpty(parsedActivity.ActivityCategory.Code) && parsedActivity.ActivityCategory.Code == ac.Code) || (!string.IsNullOrEmpty(parsedActivity.ActivityCategory.Name) && parsedActivity.ActivityCategory.Name == ac.Name))
                    ?? throw new Exception($"Activity category by: {parsedActivity.ActivityCategory.Code} code or {parsedActivity.ActivityCategory.Name} name not found");

                parsedActivity.ActivityCategory = activityCategory;
                parsedActivity.ActivityCategoryId = activityCategory.Id;
            }
            return parsedActivity;
        }

        private Address GetFilledAddress(Address parsedAddress)
        {
            var code = parsedAddress.Region?.Code?.ToUpper();
            var name = parsedAddress.Region?.Name?.ToUpper();

            var region = _ctx.Regions.AsNoTracking().FirstOrDefault(reg => !reg.IsDeleted
                && (code.HasValue()
                    && code == reg.Code.ToUpper()
                    || name.HasValue()
                    && name == reg.Name.ToUpper()))
                    ?? throw new Exception($"Address Region: `{code}` code or `{name}` name not found");

            parsedAddress.RegionId = region.Id;

            return parsedAddress;
        }

        private Country GetFilledCountry(Country parsedCountry)
        {
            return  _ctx.Countries.AsNoTracking().FirstOrDefault(c =>
                        !c.IsDeleted
                        && (string.IsNullOrWhiteSpace(parsedCountry.Code) || c.Code == parsedCountry.Code)
                        && (string.IsNullOrWhiteSpace(parsedCountry.Name) || c.Name == parsedCountry.Name))
                    ?? throw new Exception($"Country by `{parsedCountry.Code}` code or `{parsedCountry.Name}` name not found");
        }

        private ForeignParticipation GetFilledForeignParticipation(ForeignParticipation foreignParticipation)
        {
            return  _ctx.ForeignParticipations.AsNoTracking().FirstOrDefault(c =>
                        !c.IsDeleted
                        && (string.IsNullOrWhiteSpace(foreignParticipation.Code) || c.Code == foreignParticipation.Code)
                        && (string.IsNullOrWhiteSpace(foreignParticipation.Name) || c.Name == foreignParticipation.Name) || foreignParticipation.NameLanguage1 != null  && c.Name == foreignParticipation.NameLanguage1 || foreignParticipation.NameLanguage2 != null && c.Name == foreignParticipation.NameLanguage2)
                    ?? throw new Exception($"Country by `{foreignParticipation.Code}` code or `{foreignParticipation.Name}` name not found");
        }

        private LegalForm GetFilledLegalForm(LegalForm parsedLegalForm)
        {
            LegalForm lf = null;
            if (!string.IsNullOrEmpty(parsedLegalForm.Name) && !string.IsNullOrEmpty(parsedLegalForm.Code))
            {
                lf = _ctx.LegalForms.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == parsedLegalForm.Name || dsc.NameLanguage1 == parsedLegalForm.Name || dsc.NameLanguage2 == parsedLegalForm.Name) &&
                    dsc.Code == parsedLegalForm.Code);
            }
            else if (!string.IsNullOrEmpty(parsedLegalForm.Name))
            {
                lf =  _ctx.LegalForms.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == parsedLegalForm.Name || dsc.NameLanguage1 == parsedLegalForm.Name || dsc.NameLanguage2 == parsedLegalForm.Name));
            }
            else if (!string.IsNullOrEmpty(parsedLegalForm.Code))
            {
                lf = _ctx.LegalForms.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && dsc.Code == parsedLegalForm.Code);
            }

            if (lf == null)
            {
                throw new Exception($"Legal form by `{parsedLegalForm.Name}` name and {parsedLegalForm.Code} code not found");
            }

            return lf;
        }

        private Person GetFilledPerson(Person parsedPerson)
        {
            if (parsedPerson.NationalityCode?.Code != null && parsedPerson.NationalityCode?.Name != null)
            {
                // TODO: dont do it, if person exists in DB
                var country = _ctx.Countries.AsNoTracking()
                    .FirstOrDefault(c => !c.IsDeleted
                        && (parsedPerson.NationalityCode.Code.HasValue()
                        && c.Code == parsedPerson.NationalityCode.Code
                        || parsedPerson.NationalityCode.Name.HasValue()
                        && c.Name == parsedPerson.NationalityCode.Name))
                    ?? throw new Exception($"Person Nationality Code by `{parsedPerson.NationalityCode.Code}` code or `{parsedPerson.NationalityCode.Name}` name not found");
                parsedPerson.CountryId = country.Id;
            }
            return parsedPerson;
        }

        private SectorCode GetFilledSectorCode(SectorCode parsedSectorCode)
        {
            return  _ctx.SectorCodes.AsNoTracking()
                        .FirstOrDefault(sc =>
                            !sc.IsDeleted
                            && (string.IsNullOrWhiteSpace(parsedSectorCode.Code) || sc.Code == parsedSectorCode.Code)
                            && (string.IsNullOrWhiteSpace(parsedSectorCode.Name) || sc.Name == parsedSectorCode.Name))
                        ?? throw new Exception($"Sector code by `{parsedSectorCode.Code}` code or `{parsedSectorCode.Name}` name not found");
        }

        private DataSourceClassification GetFilledDataSourceClassification(DataSourceClassification parseDataSourceClassification)
        {
            DataSourceClassification ds = null;
            var name = parseDataSourceClassification.Name?.ToUpper();
            var code = parseDataSourceClassification.Code?.ToUpper();
            if (!string.IsNullOrEmpty(name) && !string.IsNullOrEmpty(code))
            {
                ds = _ctx.DataSourceClassifications.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name.ToUpper() == name || dsc.NameLanguage1.ToUpper() == name || dsc.NameLanguage2.ToUpper() == name) &&
                    dsc.Code == code);
            }else if (!string.IsNullOrEmpty(name))
            {
                ds = _ctx.DataSourceClassifications.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name.ToUpper() == name || dsc.NameLanguage1.ToUpper() == name || dsc.NameLanguage2.ToUpper() == name));
            }
            else if (!string.IsNullOrEmpty(code))
            {
                ds = _ctx.DataSourceClassifications.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && dsc.Code.ToUpper() == code);
            }

            if(ds == null)
            {
                throw new Exception($"Data source classification by `{parseDataSourceClassification.Name}` name and {parseDataSourceClassification.Code} code not found");
            }

            return ds;
        }

        private UnitSize GetFilledSize(UnitSize size)
        {
            return _ctx.UnitSizes.AsNoTracking().FirstOrDefault(s =>
                !s.IsDeleted && (s.Name == size.Name || s.NameLanguage1 == size.Name || s.NameLanguage2 == size.Name))
            ?? throw new Exception($"Size with {size.Name} name wasn't found");
        }

        private UnitStatus GetFilledUnitStatus(UnitStatus unitStatus)
        {
            UnitStatus us = null;
            if (!string.IsNullOrEmpty(unitStatus.Name) && !string.IsNullOrEmpty(unitStatus.Code))
            {
                us = _ctx.UnitStatuses.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == unitStatus.Name || dsc.NameLanguage1 == unitStatus.Name || dsc.NameLanguage2 == unitStatus.Name) &&
                    dsc.Code == unitStatus.Code);
            }
            else if (!string.IsNullOrEmpty(unitStatus.Name))
            {
                us = _ctx.UnitStatuses.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == unitStatus.Name || dsc.NameLanguage1 == unitStatus.Name || dsc.NameLanguage2 == unitStatus.Name));
            }
            else if (!string.IsNullOrEmpty(unitStatus.Code))
            {
                us = _ctx.UnitStatuses.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && dsc.Code == unitStatus.Code);
            }

            if (us == null)
            {
                throw new Exception($"Unit status by `{unitStatus.Name}` name and {unitStatus.Code} code not found");
            }

            return us;
        }

        private ReorgType GetFilledReorgType(ReorgType reorgType)
        {
            ReorgType rt = null;
            if (!string.IsNullOrEmpty(reorgType.Name) && !string.IsNullOrEmpty(reorgType.Code))
            {
                rt = _ctx.ReorgTypes.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == reorgType.Name || dsc.NameLanguage1 == reorgType.Name || dsc.NameLanguage2 == reorgType.Name) &&
                    dsc.Code == reorgType.Code);
            }
            else if (!string.IsNullOrEmpty(reorgType.Name))
            {
                rt = _ctx.ReorgTypes.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == reorgType.Name || dsc.NameLanguage1 == reorgType.Name || dsc.NameLanguage2 == reorgType.Name));
            }
            else if (!string.IsNullOrEmpty(reorgType.Code))
            {
                rt = _ctx.ReorgTypes.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && dsc.Code == reorgType.Code);
            }

            if (rt == null)
            {
                throw new Exception($"Reorg type by `{reorgType.Name}` name and {reorgType.Code} code not found");
            }

            return rt;
        }

        private RegistrationReason GetFilledRegistrationReason(RegistrationReason registrationReason)
        {
            RegistrationReason rr = null;
            if (!string.IsNullOrEmpty(registrationReason.Name) && !string.IsNullOrEmpty(registrationReason.Code))
            {
                rr = _ctx.RegistrationReasons.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == registrationReason.Name || dsc.NameLanguage1 == registrationReason.Name || dsc.NameLanguage2 == registrationReason.Name) &&
                    dsc.Code == registrationReason.Code);
            }
            else if (!string.IsNullOrEmpty(registrationReason.Name))
            {
                rr = _ctx.RegistrationReasons.AsNoTracking().FirstOrDefault(dsc =>
                    !dsc.IsDeleted && (dsc.Name == registrationReason.Name || dsc.NameLanguage1 == registrationReason.Name || dsc.NameLanguage2 == registrationReason.Name));
            }
            else if (!string.IsNullOrEmpty(registrationReason.Code))
            {
                rr = _ctx.RegistrationReasons.AsNoTracking().FirstOrDefault(dsc =>
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
