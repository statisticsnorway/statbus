using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Validators.Extentions;
using nscreg.Utilities;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using Activity = nscreg.Data.Entities.Activity;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;
using Person = nscreg.Data.Entities.Person;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class EditService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly UserService _userService;
        private readonly Common _commonSvc;
        private readonly ElasticService _elasticService;

        public EditService(NSCRegDbContext dbContext, StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields mandatoryFields)
        {
            _dbContext = dbContext;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _mandatoryFields = mandatoryFields;
            _userService = new UserService(dbContext);
            _commonSvc = new Common(dbContext);
            _elasticService = new ElasticService(dbContext);
        }

        /// <summary>
        /// Метод редактирования правовой единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> EditLegalUnit(LegalUnitEditM data, string userId)
            => await EditUnitContext<LegalUnit, LegalUnitEditM>(
                data,
                m => m.RegId ?? 0,
                userId,
                unit =>
                {
                    if (Common.HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                    {
                        var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                        unit.LocalUnits.Clear();
                        unit.HistoryLocalUnitIds = null;
                        if (data.LocalUnits == null) return Task.CompletedTask;
                        foreach (var localUnit in localUnits)
                        {
                            unit.LocalUnits.Add(localUnit);
                        }

                        if (data.LocalUnits != null)
                            unit.HistoryLocalUnitIds = string.Join(",", data.LocalUnits);
                    }
                    return Task.CompletedTask;
                });

        /// <summary>
        /// Метод редактирования местной единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> EditLocalUnit(LocalUnitEditM data, string userId)
            => await EditUnitContext<LocalUnit, LocalUnitEditM>(
                data,
                v => v.RegId ?? 0,
                userId,
                null);

        /// <summary>
        /// Метод редактирования предприятия
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> EditEnterpriseUnit(EnterpriseUnitEditM data, string userId)
            => await EditUnitContext<EnterpriseUnit, EnterpriseUnitEditM>(
                data,
                m => m.RegId ?? 0,
                userId,
                unit =>
                {
                    if (Common.HasAccess<EnterpriseUnit>(data.DataAccess, v => v.LegalUnits))
                    {
                        var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId));
                        unit.LegalUnits.Clear();
                        unit.HistoryLegalUnitIds = null;
                        foreach (var legalUnit in legalUnits)
                        {
                            unit.LegalUnits.Add(legalUnit);
                        }

                        if (data.LegalUnits != null)
                            unit.HistoryLegalUnitIds = string.Join(",", data.LegalUnits);
                    }
                    return Task.CompletedTask;
                });

        /// <summary>
        /// Метод редактирования группы предприятий
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> EditEnterpriseGroup(EnterpriseGroupEditM data, string userId)
            => await EditContext<EnterpriseGroup, EnterpriseGroupEditM>(
                data,
                m => m.RegId ?? 0,
                userId,
                unit =>
                {
                    if (Common.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                    {
                        var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId));
                        unit.EnterpriseUnits.Clear();
                        unit.HistoryEnterpriseUnitIds = null;
                        foreach (var enterprise in enterprises)
                        {
                            unit.EnterpriseUnits.Add(enterprise);
                        }

                        if (data.EnterpriseUnits != null)
                            unit.HistoryEnterpriseUnitIds = string.Join(",", data.EnterpriseUnits);
                    }

                    return Task.CompletedTask;
                });

        /// <summary>
        /// Метод редактирования контекста стат. единцы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="idSelector">Id Селектора</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="work">В работе</param>
        /// <returns></returns>
        private async Task<Dictionary<string, string[]>> EditUnitContext<TUnit, TModel>(
            TModel data,
            Func<TModel, int> idSelector,
            string userId,
            Func<TUnit, Task> work)
            where TModel : StatUnitModelBase
            where TUnit : StatisticalUnit, new()
            => await EditContext<TUnit, TModel>(
                data,
                idSelector,
                userId,
                async unit =>
                {
                    //Merge activities
                    if (Common.HasAccess<TUnit>(data.DataAccess, v => v.Activities))
                    {
                        var activities = new List<ActivityStatisticalUnit>();
                        var srcActivities = unit.ActivitiesUnits.ToDictionary(v => v.ActivityId);
                        var activitiesList = data.Activities ?? new List<ActivityM>();

                        foreach (var model in activitiesList)
                        {
                            if (model.Id.HasValue && srcActivities.TryGetValue(model.Id.Value,
                                    out ActivityStatisticalUnit activityAndUnit))
                            {
                                var currentActivity = activityAndUnit.Activity;
                                if (model.ActivityCategoryId == currentActivity.ActivityCategoryId &&
                                    ObjectComparer.SequentialEquals(model, currentActivity))
                                {
                                    activities.Add(activityAndUnit);
                                    continue;
                                }
                            }
                            var newActivity = new Activity();
                            Mapper.Map(model, newActivity);
                            newActivity.UpdatedBy = userId;
                            newActivity.ActivityCategoryId = model.ActivityCategoryId;
                            activities.Add(new ActivityStatisticalUnit() {Activity = newActivity});
                        }
                        var activitiesUnits = unit.ActivitiesUnits;
                        activitiesUnits.Clear();
                        unit.ActivitiesUnits.AddRange(activities);
                    }


                    var srcCountries = unit.ForeignParticipationCountriesUnits.ToDictionary(v => v.CountryId);
                    var countriesList = data.ForeignParticipationCountriesUnits ?? new List<int>();
                    var countryBindingsToAdd = countriesList.Where(id => !srcCountries.ContainsKey(id)).ToList();
                    foreach (var id in countryBindingsToAdd)
                        unit.ForeignParticipationCountriesUnits.Add(
                            new CountryStatisticalUnit {CountryId = id});

                    var countryBindingsToRemove = srcCountries
                        .Where(b => !countriesList.Contains(b.Key)).Select(x => x.Value).ToList();

                    foreach (var binding in countryBindingsToRemove)
                        unit.ForeignParticipationCountriesUnits.Remove(binding);

                    var persons = new List<PersonStatisticalUnit>();
                    var srcPersons = unit.PersonsUnits.ToDictionary(v => v.PersonId);
                    var personsList = data.Persons ?? new List<PersonM>();

                    foreach (var model in personsList)
                    {
                        if (model.Id.HasValue && srcPersons.TryGetValue(model.Id.Value,
                                out PersonStatisticalUnit personStatisticalUnit))
                        {
                            var currentPerson = personStatisticalUnit.Person;
                            if (model.Id == currentPerson.Id )
                            {
                                currentPerson.UpdateProperties(model);
                                personStatisticalUnit.PersonType = currentPerson.Role;
                                persons.Add(personStatisticalUnit);
                                continue;
                            }
                        }
                        var newPerson = new Person();
                        Mapper.Map(model, newPerson);
                        persons.Add(new PersonStatisticalUnit {Person = newPerson, PersonType = newPerson.Role});
                    }
                    var statUnits = unit.PersonsUnits.Where(su => su.StatUnitId != null)
                        .ToDictionary(su => su.StatUnitId);
                    var statUnitsList = data.PersonStatUnits ?? new List<PersonStatUnitModel>();

                    foreach (var unitM in statUnitsList)
                    {
                        if (unitM.StatRegId.HasValue && statUnits.TryGetValue(unitM.StatRegId.Value,
                                out var personStatisticalUnit))
                        {
                            var currentUnit = personStatisticalUnit.StatUnit;
                            if (unitM.StatRegId == currentUnit.RegId)
                            {
                                currentUnit.UpdateProperties(unitM);
                                persons.Add(personStatisticalUnit);
                                continue;
                            }
                        }
                        persons.Add(new PersonStatisticalUnit
                        {
                            UnitId = unit.RegId,
                            StatUnitId = unitM.StatRegId,
                            EnterpriseGroupId = null,
                            PersonId = null,
                            PersonType = unitM.Role
                        });
                    }

                    var groupUnits = unit.PersonsUnits.Where(su => su.EnterpriseGroupId != null)
                        .ToDictionary(su => su.EnterpriseGroupId);

                    foreach (var unitM in statUnitsList)
                    {
                        if (unitM.GroupRegId.HasValue &&
                            groupUnits.TryGetValue(unitM.GroupRegId, out var personStatisticalUnit))
                        {
                            var currentUnit = personStatisticalUnit.StatUnit;
                            if (unitM.GroupRegId == currentUnit.RegId)
                            {
                                currentUnit.UpdateProperties(unitM);
                                persons.Add(personStatisticalUnit);
                                continue;
                            }
                        }
                        persons.Add(new PersonStatisticalUnit
                        {
                            UnitId = unit.RegId,
                            EnterpriseGroupId = unitM.GroupRegId,
                            StatUnitId = null,
                            PersonId = null,
                            PersonType = unitM.Role
                        });
                    }

                    var statisticalUnits = unit.PersonsUnits;
                    statisticalUnits.Clear();
                    unit.PersonsUnits.AddRange(persons);

                    if (work != null)
                    {
                        await work(unit);
                    }
                });

        /// <summary>
        /// Метод редактирования контекста
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="idSelector">Id Селектора</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="work">В работе</param>
        /// <returns></returns>
        private async Task<Dictionary<string, string[]>> EditContext<TUnit, TModel>(
            TModel data,
            Func<TModel, int> idSelector,
            string userId,
            Func<TUnit, Task> work)
            where TModel : IStatUnitM
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = (TUnit) await ValidateChanges<TUnit>(idSelector(data));
            await _commonSvc.InitializeDataAccessAttributes(_userService, data, userId, unit.UnitType);

            var unitsHistoryHolder = new UnitsHistoryHolder(unit);

            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);
            Mapper.Map(data, unit);

            var deleteEnterprise = false;
            var existingLeuEntRegId = (int?) 0;
            if (unit is LegalUnit)
            {
                var legalUnit = unit as LegalUnit;
                existingLeuEntRegId = _dbContext.LegalUnits.Where(leu => leu.RegId == legalUnit.RegId)
                    .Select(leu => leu.EnterpriseUnitRegId).FirstOrDefault();
                if (existingLeuEntRegId != legalUnit.EnterpriseUnitRegId &&
                    !_dbContext.LegalUnits.Any(leu => leu.EnterpriseUnitRegId == existingLeuEntRegId))
                    deleteEnterprise = true;
            }

            //External Mappings
            if (work != null)
            {
                await work(unit);
            }

            _commonSvc.AddAddresses<TUnit>(unit, data);
            if (IsNoChanges(unit, hUnit)) return null;

            unit.UserId = userId;
            unit.ChangeReason = data.ChangeReason;
            unit.EditComment = data.EditComment;

            IStatUnitAnalyzeService analysisService =
                new AnalyzeService(_dbContext, _statUnitAnalysisRules, _mandatoryFields);
            var analyzeResult = analysisService.AnalyzeStatUnit(unit);
            if (analyzeResult.Messages.Any()) return analyzeResult.Messages;

            _dbContext.Set<TUnit>().Add((TUnit) Common.TrackHistory(unit, hUnit));

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    var changeDateTime = DateTime.Now;
                    _dbContext.Set<TUnit>().Add((TUnit) Common.TrackHistory(unit, hUnit, changeDateTime));
                    await _dbContext.SaveChangesAsync();

                    _commonSvc.TrackRelatedUnitsHistory(unit, hUnit, userId, data.ChangeReason, data.EditComment,
                        changeDateTime, unitsHistoryHolder);
                    await _dbContext.SaveChangesAsync();

                    if (deleteEnterprise)
                    {
                        _dbContext.EnterpriseUnits.Remove(_dbContext.EnterpriseUnits.First(eu => eu.RegId == existingLeuEntRegId));
                        await _dbContext.SaveChangesAsync();
                    }

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    //TODO: Processing Validation Errors
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
                await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(unit));
            }

            return null;
        }

        /// <summary>
        /// Метод валидации изменений данных
        /// </summary>
        /// <param name="regid">Регистрационный Id</param>
        /// <returns></returns>
        private async Task<IStatisticalUnit> ValidateChanges<T>(int regid)
            where T : class, IStatisticalUnit
        {
            var unit = await _commonSvc.GetStatisticalUnitByIdAndType(
                regid,
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(typeof(T)),
                false);

            return unit;
        }

        /// <summary>
        /// Метод проверки на неизменность данных
        /// </summary>
        /// <param name="unit">Стат. единицы</param>
        /// <param name="hUnit">История стат. единицы</param>
        /// <returns></returns>
        private static bool IsNoChanges(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var unitType = unit.GetType();
            var propertyInfo = unitType.GetProperties();
            foreach (var property in propertyInfo)
            {
                var unitProperty = unitType.GetProperty(property.Name).GetValue(unit, null);
                var hUnitProperty = unitType.GetProperty(property.Name).GetValue(hUnit, null);
                if (!Equals(unitProperty, hUnitProperty)) return false;
            }
            if (!(unit is StatisticalUnit statUnit)) return true;
            var hstatUnit = (StatisticalUnit) hUnit;
            return hstatUnit.ActivitiesUnits.CompareWith(statUnit.ActivitiesUnits, v => v.ActivityId)
                   && hstatUnit.PersonsUnits.CompareWith(statUnit.PersonsUnits, p => p.PersonId);
        }

    }
}
