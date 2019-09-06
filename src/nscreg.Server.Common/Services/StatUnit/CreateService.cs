using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using Activity = nscreg.Data.Entities.Activity;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;
using Person = nscreg.Data.Entities.Person;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис создания
    /// </summary>
    public class CreateService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly UserService _userService;
        private readonly Common _commonSvc;
        private readonly ValidationSettings _validationSettings;
        private readonly DataAccessService _dataAccessService;

        public CreateService(NSCRegDbContext dbContext, StatUnitAnalysisRules statUnitAnalysisRules, DbMandatoryFields mandatoryFields, ValidationSettings validationSettings)
        {
            _dbContext = dbContext;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _mandatoryFields = mandatoryFields;
            _userService = new UserService(dbContext);
            _commonSvc = new Common(dbContext);
            _validationSettings = validationSettings;
            _dataAccessService = new DataAccessService(dbContext);
        }

        private void CheckRegionOrActivityContains(string userId, int? regionId, int? actualRegionId, int? postalRegionId, List<ActivityM> activityCategoryList)
        {
            if (!_userService.IsInRoleAsync(userId, DefaultRoleNames.Employee).Result) return;
            CheckIfRegionContains(userId, regionId, actualRegionId, postalRegionId);
            CheckIfActivityContains(userId, activityCategoryList);
        }

        private void CheckIfRegionContains(string userId, int? regionId, int? actualRegionId, int? postalRegionId)
        {
            var regionIds = _dbContext.UserRegions.Where(au => au.UserId == userId).Select(ur => ur.RegionId).ToList();

            if (regionIds.Count == 0)
                throw new BadRequestException(Resource.YouDontHaveEnoughtRightsRegion);
            var listRegions = new List<int>();
            if (regionId != null && !regionIds.Contains((int) regionId))
                listRegions.Add((int) regionId);
            if (actualRegionId != null && !regionIds.Contains((int) actualRegionId))
                listRegions.Add((int) actualRegionId);
            if (postalRegionId != null && !regionIds.Contains((int) postalRegionId))
                listRegions.Add((int) postalRegionId);
            if (listRegions.Count > 0)
            {
                var regionNames = _dbContext.Regions.Where(x => listRegions.Contains(x.Id))
                    .Select(x => new CodeLookupBase{ Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2}.GetString(CultureInfo.DefaultThreadCurrentCulture)).ToList();
                throw new BadRequestException($"{Resource.YouDontHaveEnoughtRightsRegion} ({string.Join(",",regionNames.Distinct())}");
            }
        }

        private void CheckIfActivityContains(string userId, List<ActivityM> activityCategoryList)
        {
            foreach (var activityCategory in activityCategoryList)
            {
                if (activityCategory?.ActivityCategoryId == null)
                    throw new BadRequestException($"{Resource.YouDontHaveEnoughtRightsActivityCategory}");
                
                var activityCategoryUserIds = _dbContext.ActivityCategoryUsers.Where(au => au.UserId == userId)
                    .Select(ur => ur.ActivityCategoryId).ToList();
                if (activityCategoryUserIds.Count == 0 || !activityCategoryUserIds.Contains(activityCategory.ActivityCategoryId))
                {
                    var activityCategoryNames =
                        _dbContext.ActivityCategories.Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1,NameLanguage2 = x.NameLanguage2, Id = x.Id }).FirstOrDefault(x => x.Id == activityCategory.ActivityCategoryId);

                    var langName = activityCategoryNames.GetString(CultureInfo.DefaultThreadCurrentCulture);
                    throw new BadRequestException($"{Resource.YouDontHaveEnoughtRightsActivityCategory} ({langName})");
                }
            }
        }
        /// <summary>
        /// Метод создания правовой единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateLegalUnit(LegalUnitCreateM data, string userId)
            => await CreateUnitContext<LegalUnit, LegalUnitCreateM>(data, userId, unit =>
            {
                CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, data.Activities);
                if (Common.HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                {
                    if (data.LocalUnits == null) return Task.CompletedTask;
                    var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
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
        /// Метод создания местной единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateLocalUnit(LocalUnitCreateM data, string userId)
        {
            CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, data.Activities);
            return await CreateUnitContext<LocalUnit, LocalUnitCreateM>(data, userId, null);
        }

        /// <summary>
        /// Метод создания предприятия
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateEnterpriseUnit(EnterpriseUnitCreateM data, string userId)
            => await CreateUnitContext<EnterpriseUnit, EnterpriseUnitCreateM>(data, userId, unit =>
            {
                CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, data.Activities);
                var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                foreach (var legalUnit in legalUnits)
                {
                    unit.LegalUnits.Add(legalUnit);
                }

                if (data.LegalUnits != null)
                    unit.HistoryLegalUnitIds = string.Join(",", data.LegalUnits);

                return Task.CompletedTask;
            });

        /// <summary>
        /// Метод создания группы предприятия
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateEnterpriseGroup(EnterpriseGroupCreateM data, string userId)
            => await CreateContext<EnterpriseGroup, EnterpriseGroupCreateM>(data, userId, unit =>
            {
                CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, new List<ActivityM>());
                if (Common.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                {
                    var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId))
                        .ToList();
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
        /// Метод создания контекста стат. единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="work">В работе</param>
        /// <returns></returns>
        private async Task<Dictionary<string, string[]>> CreateUnitContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work)
            where TModel : StatUnitModelBase
            where TUnit : StatisticalUnit, new()
            => await CreateContext<TUnit, TModel>(data, userId, async unit =>
            {
                if (Common.HasAccess<TUnit>(data.DataAccess, v => v.Activities))
                {
                    var activitiesList = data.Activities ?? new List<ActivityM>();

                    unit.ActivitiesUnits.AddRange(activitiesList.Select(v =>
                        {
                            var activity = Mapper.Map<ActivityM, Activity>(v);
                            activity.Id = 0;
                            activity.ActivityCategoryId = v.ActivityCategoryId;
                            activity.UpdatedBy = userId;
                            return new ActivityStatisticalUnit {Activity = activity};
                        }
                    ));
                }

                var personList = data.Persons ?? new List<PersonM>();

                unit.PersonsUnits.AddRange(personList.Select(v =>
                {
                    var person = Mapper.Map<PersonM, Person>(v);
                    person.Id = 0;
                    return new PersonStatisticalUnit { Person = person, PersonTypeId = v.Role };
                }));

                var statUnits = data.PersonStatUnits ?? new List<PersonStatUnitModel>();
                foreach (var unitM in statUnits)
                {
                    if (unitM.StatRegId == null)
                        unit.PersonsUnits.Add(new PersonStatisticalUnit
                        {
                            EnterpriseGroupId = unitM.GroupRegId,
                            StatUnitId = null,
                            PersonId = null,
                            PersonTypeId = unitM.RoleId
                        });
                    else
                        unit.PersonsUnits.Add(new PersonStatisticalUnit
                        {
                            StatUnitId = unitM.StatRegId,
                            EnterpriseGroupId = null,
                            PersonId = null,
                            PersonTypeId = unitM.RoleId
                        });
                }

                var countriesList = data.ForeignParticipationCountriesUnits ?? new List<int>();

                unit.ForeignParticipationCountriesUnits.AddRange(countriesList.Select(v => new CountryStatisticalUnit { CountryId = v }));

                if (work != null)
                {
                    await work(unit);
                }
            });

        /// <summary>
        /// Метод создания контекста
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="work">В работе</param>
        /// <returns></returns>
        private async Task<Dictionary<string, string[]>> CreateContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work)
            where TModel : IStatUnitM
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = new TUnit();
            if (_dataAccessService.CheckWritePermissions(userId, unit.UnitType))
            {
                return new Dictionary<string, string[]> { { nameof(UserAccess.UnauthorizedAccess), new[] { nameof(Resource.Error403) } } };
            }

            await _commonSvc.InitializeDataAccessAttributes(_userService, data, userId, unit.UnitType);
            Mapper.Map(data, unit);
            _commonSvc.AddAddresses<TUnit>(unit, data);

            if (work != null)
            {
                await work(unit);
            }

            unit.UserId = userId;

            IStatUnitAnalyzeService analysisService = new AnalyzeService(_dbContext, _statUnitAnalysisRules, _mandatoryFields, _validationSettings);
            var analyzeResult = analysisService.AnalyzeStatUnit(unit);
            if (analyzeResult.Messages.Any()) return analyzeResult.Messages;

            var helper = new StatUnitCreationHelper(_dbContext);

            if (unit is LocalUnit)
                await helper.CreateLocalUnit(unit as LocalUnit);
            else if (unit is LegalUnit)
                await helper.CreateLegalWithEnterpriseAndLocal(unit as LegalUnit);
            else if (unit is EnterpriseUnit)
                await helper.CreateEnterpriseWithGroup(unit as EnterpriseUnit);
            else if (unit is EnterpriseGroup)
                await helper.CreateGroup(unit as EnterpriseGroup);

            return null;
        }
    }
}
