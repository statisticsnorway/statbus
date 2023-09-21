using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Validators.Extensions;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
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
        private readonly CommonService _commonSvc;
        private readonly ElasticService _elasticService;
        private readonly ValidationSettings _validationSettings;
        private readonly DataAccessService _dataAccessService;
        private readonly int? _liquidateStatusId;
        private readonly List<ElasticStatUnit> _editArrayStatisticalUnits;
        private readonly List<ElasticStatUnit> _addArrayStatisticalUnits;
        private readonly bool _shouldAnalyze;
        private readonly IMapper _mapper;
        //private readonly IStatUnitAnalyzeService _analysisService;

        public EditService(NSCRegDbContext dbContext, StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields mandatoryFields, ValidationSettings validationSettings,
            //IStatUnitAnalyzeService analysisService,
            IMapper mapper, bool shouldAnalyze = true)
        {
            _dbContext = dbContext;            
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _mandatoryFields = mandatoryFields;
            //TODO User service not create new
            _userService = new UserService(dbContext, _mapper);
            _commonSvc = new CommonService(dbContext, mapper,null);
            _elasticService = new ElasticService(dbContext, mapper);
            _validationSettings = validationSettings;
            _dataAccessService = new DataAccessService(dbContext, _mapper);
            _liquidateStatusId = _dbContext.UnitStatuses.FirstOrDefault(x => x.Code == "7")?.Id;
            _editArrayStatisticalUnits = new List<ElasticStatUnit>();
            _addArrayStatisticalUnits = new List<ElasticStatUnit>();
            _shouldAnalyze = shouldAnalyze;
            //_analysisService = analysisService;
            _mapper = mapper;
        }

        /// <summary>
        /// Method of editing a legal unit
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        public async Task<Dictionary<string, string[]>> EditLegalUnit(LegalUnitEditM data, string userId)
            => await EditUnitContext<LegalUnit, LegalUnitEditM>(
                data,
                m => m.RegId ?? 0,
                userId, (unit) =>
                {
                    if (!CommonService.HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                    {
                        return Task.CompletedTask;
                    }
                    if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
                    {
                        var enterpriseUnit = _dbContext.EnterpriseUnits.Include(x => x.LegalUnits).FirstOrDefault(x => unit.EnterpriseUnitRegId == x.RegId);
                        var legalUnits = enterpriseUnit?.LegalUnits.Where(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId).ToList();
                        if (enterpriseUnit != null && legalUnits.Count == 0)
                        {
                            enterpriseUnit.UnitStatusId = unit.UnitStatusId;
                            enterpriseUnit.LiqReason = unit.LiqReason;
                            enterpriseUnit.LiqDate = unit.LiqDate;
                            _editArrayStatisticalUnits.Add(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterpriseUnit));
                        }
                    }

                    if (data.LocalUnits != null && data.LocalUnits.Any())
                    {
                        var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId) && x.UnitStatusId != _liquidateStatusId);

                        unit.LocalUnits.Clear();
                        unit.HistoryLocalUnitIds = null;
                        foreach (var localUnit in localUnits)
                        {
                            if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
                            {
                                localUnit.UnitStatusId = unit.UnitStatusId;
                                localUnit.LiqReason = unit.LiqReason;
                                localUnit.LiqDate = unit.LiqDate;
                            }
                            unit.LocalUnits.Add(localUnit);
                            _addArrayStatisticalUnits.Add(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(localUnit));
                        }
                        unit.HistoryLocalUnitIds = string.Join(",", data.LocalUnits);
                    }
                    return Task.CompletedTask;
                });

        /// <summary>
        /// Local unit editing method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        public async Task<Dictionary<string, string[]>> EditLocalUnit(LocalUnitEditM data, string userId)
            => await EditUnitContext<LocalUnit, LocalUnitEditM>(
                data,
                v => v.RegId ?? 0,
                userId,
                unit =>
                {
                    if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
                    {
                        var legalUnit = _dbContext.LegalUnits.Include(x => x.LocalUnits).FirstOrDefault(x => unit.LegalUnitId == x.RegId && !x.IsDeleted);
                        if (legalUnit != null && legalUnit.LocalUnits.Where(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId.Value).ToList().Count == 0)
                        {
                            throw new BadRequestException(nameof(Resource.LiquidateLegalUnit));
                        }
                    } 
                    return Task.CompletedTask;
                });

        /// <summary>
        /// Enterprise editing method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        public async Task<Dictionary<string, string[]>> EditEnterpriseUnit(EnterpriseUnitEditM data, string userId)
            => await EditUnitContext<EnterpriseUnit, EnterpriseUnitEditM>(
                data,
                m => m.RegId ?? 0,
                userId,
                unit =>
                {
                    if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
                    {
                        throw new BadRequestException(nameof(Resource.LiquidateEntrUnit));
                    }
                    if (CommonService.HasAccess<EnterpriseUnit>(data.DataAccess, v => v.LegalUnits))
                    {
                        if (data.LegalUnits != null && data.LegalUnits.Any())
                        {
                            var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId));
                            unit.LegalUnits.Clear();
                            unit.HistoryLegalUnitIds = null;
                            foreach (var legalUnit in legalUnits)
                            {
                                unit.LegalUnits.Add(legalUnit);
                                _addArrayStatisticalUnits.Add(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(legalUnit));
                            }
                            
                            unit.HistoryLegalUnitIds = string.Join(",", data.LegalUnits);
                        }
                            
                    }
                    return Task.CompletedTask;
                });

        /// <summary>
        /// Method of editing a group of enterprises
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        public async Task<Dictionary<string, string[]>> EditEnterpriseGroup(EnterpriseGroupEditM data, string userId)
            => await EditContext<EnterpriseGroup, EnterpriseGroupEditM>(
                data,
                m => m.RegId ?? 0,
                userId,
                (unit, oldUnit) =>
                {
                    if (CommonService.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                    {
                        if (data.EnterpriseUnits != null && data.EnterpriseUnits.Any())
                        {
                            var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId));
                            unit.EnterpriseUnits.Clear();
                            unit.HistoryEnterpriseUnitIds = null;
                            foreach (var enterprise in enterprises)
                            {
                                unit.EnterpriseUnits.Add(enterprise);
                                _addArrayStatisticalUnits.Add(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterprise));
                            }
                            unit.HistoryEnterpriseUnitIds = string.Join(",", data.EnterpriseUnits);
                        }
                    }

                    return Task.CompletedTask;
                });

        /// <summary>
        /// Method for editing the context stat. Edinet
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "idSelector"> Id Selector </param>
        /// <param name = "userId"> User Id </param>
        /// <param name = "work"> At work </param>
        /// <returns> </returns>
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
                async (unit, oldUnit) =>
                {
                    //Merge activities
                    if (CommonService.HasAccess<TUnit>(data.DataAccess, v => v.Activities))
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
                            _mapper.Map(model, newActivity);
                            newActivity.UpdatedBy = userId;
                            newActivity.ActivityCategoryId = model.ActivityCategoryId;
                            activities.Add(new ActivityStatisticalUnit() {Activity = newActivity});
                        }
                        unit.ActivitiesUnits.Clear();
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
                        if (model.Id.HasValue && model.Id > 0)
                        {
                            if (srcPersons.TryGetValue(model.Id.Value, out PersonStatisticalUnit personStatisticalUnit))
                            {
                                var currentPerson = personStatisticalUnit.Person;
                                if (model.Id == currentPerson.Id)
                                {
                                    currentPerson.UpdateProperties(model);
                                    persons.Add(personStatisticalUnit);
                                    continue;
                                }
                            } else
                            {
                                persons.Add(new PersonStatisticalUnit { PersonId = (int)model.Id, PersonTypeId = model.Role });
                                continue;
                            }
                        }
                        var newPerson = _mapper.Map<PersonM, Person>(model);
                        persons.Add(new PersonStatisticalUnit { Person = newPerson, PersonTypeId = model.Role });
                    }

                    var statUnitsList = data.PersonStatUnits ?? new List<PersonStatUnitModel>();

                    foreach (var unitM in statUnitsList)
                    {
                        if (unitM.StatRegId.HasValue )
                        {
                            var personStatisticalUnit = unit.PersonsUnits.First(x => x.UnitId == unitM.StatRegId.Value);
                            var currentUnit = personStatisticalUnit.Unit;
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
                            EnterpriseGroupId = null,
                            PersonId = null,
                            PersonTypeId = unitM.RoleId
                        });
                    }

                    var groupUnits = unit.PersonsUnits.Where(su => su.EnterpriseGroupId != null).GroupBy(x => x.EnterpriseGroupId)
                        .ToDictionary(su => su.Key, su => su.First());

                    foreach (var unitM in statUnitsList)
                    {
                        if (unitM.GroupRegId.HasValue &&
                            groupUnits.TryGetValue(unitM.GroupRegId, out var personStatisticalUnit))
                        {
                            var currentUnit = personStatisticalUnit.Unit;
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
                            PersonId = null
                        });
                    }

                    unit.PersonsUnits.Clear();
                    unit.PersonsUnits.AddRange(persons);

                    if (data.LiqDate != null || !string.IsNullOrEmpty(data.LiqReason) || (_liquidateStatusId != null && data.UnitStatusId == _liquidateStatusId))
                    {
                        unit.UnitStatusId = _liquidateStatusId;
                        unit.LiqDate = unit.LiqDate ?? DateTime.Now;
                    }

                    if ((oldUnit.LiqDate != null && data.LiqDate == null)  || (!string.IsNullOrEmpty(oldUnit.LiqReason) &&  string.IsNullOrEmpty(data.LiqReason)))
                    {
                        unit.LiqDate = oldUnit.LiqDate != null && data.LiqDate == null ? oldUnit.LiqDate : data.LiqDate;
                        unit.LiqReason = !string.IsNullOrEmpty(oldUnit.LiqReason) && string.IsNullOrEmpty(data.LiqReason) ? oldUnit.LiqReason : data.LiqReason;
                    }

                    if (work != null)
                    {
                        await work(unit);
                    }
                    
                });

        /// <summary>
        /// Context editing method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "idSelector"> Id Selector </param>
        /// <param name = "userId"> User Id </param>
        /// <param name = "work"> At work </param>
        /// <returns> </returns>
        private async Task<Dictionary<string, string[]>> EditContext<TUnit, TModel>(
            TModel data,
            Func<TModel, int> idSelector,
            string userId,
            Func<TUnit, TUnit, Task> work)
            where TModel : IStatUnitM
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = (TUnit) await ValidateChanges<TUnit>(idSelector(data));
            if (_dataAccessService.CheckWritePermissions(userId, unit.UnitType))
            {
                return new Dictionary<string, string[]> { { nameof(UserAccess.UnauthorizedAccess), new []{ nameof(Resource.Error403) } } };
            }

            await _commonSvc.InitializeDataAccessAttributes(_userService, data, userId, unit.UnitType);

            var unitsHistoryHolder = new UnitsHistoryHolder(unit);

            var hUnit = new TUnit();
            _mapper.Map(unit, hUnit);
            _mapper.Map(data, unit);


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

            if (_liquidateStatusId != null && hUnit.UnitStatusId == _liquidateStatusId && unit.UnitStatusId != hUnit.UnitStatusId)
            {
                throw new BadRequestException(nameof(Resource.UnitHasLiquidated));
            }
            
            //External Mappings
            if (work != null)
            {
                await work(unit, hUnit);
            }

            await _commonSvc.AddAddresses<TUnit>(unit, data);
            if (IsNoChanges(unit, hUnit)) return null;

            unit.UserId = userId;
            unit.ChangeReason = data.ChangeReason;
            unit.EditComment = data.EditComment;

            if (_shouldAnalyze)
            {
                IStatUnitAnalyzeService analysisService =
                new AnalyzeService(_dbContext, _statUnitAnalysisRules, _mandatoryFields, _validationSettings);
                var analyzeResult = await analysisService.AnalyzeStatUnit(unit, isSkipCustomCheck: true);
                if (analyzeResult.Messages.Any()) return analyzeResult.Messages;
            }

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(hUnit);
                    var changedDateTime = DateTime.Now;
                    _commonSvc.AddHistoryUnitByType(CommonService.TrackHistory(unit, mappedHistoryUnit, changedDateTime));

                    _commonSvc.TrackRelatedUnitsHistory(unit, hUnit, userId, data.ChangeReason, data.EditComment,
                        changedDateTime, unitsHistoryHolder);


                    if (deleteEnterprise)
                    {
                        _dbContext.EnterpriseUnits.Remove(_dbContext.EnterpriseUnits.First(eu => eu.RegId == existingLeuEntRegId));
                    }

                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                    await _elasticService.CheckElasticSearchConnection();
                    if (_addArrayStatisticalUnits.Any())
                        foreach (var addArrayStatisticalUnit in _addArrayStatisticalUnits)
                        {
                            await _elasticService.AddDocument(addArrayStatisticalUnit);
                        }
                    if (_editArrayStatisticalUnits.Any())
                        foreach (var editArrayStatisticalUnit in _editArrayStatisticalUnits)
                        {
                            await _elasticService.EditDocument(editArrayStatisticalUnit);
                        }

                    await _elasticService.EditDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(unit));
                }
                catch (NotFoundException e)
                {
                    throw new BadRequestException(nameof(Resource.ElasticSearchIsDisable), e);
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }

            return null;
        }

        /// <summary>
        /// Method for validating data changes
        /// </summary>
        /// <param name = "regid"> Registration Id </param>
        /// <returns> </returns>
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
        /// Method for checking for data immutability
        /// </summary>
        /// <param name = "unit"> Stat. units </param>
        /// <param name = "hUnit"> History of stat. units </param>
        /// <returns> </returns>
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
