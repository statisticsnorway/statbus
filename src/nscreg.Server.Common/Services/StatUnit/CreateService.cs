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
using nscreg.Utilities.Enums;
using Activity = nscreg.Data.Entities.Activity;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;
using Person = nscreg.Data.Entities.Person;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Class service creation
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
        private readonly StatUnitTypeOfSave _statUnitTypeOfSave;

        public CreateService(NSCRegDbContext dbContext, StatUnitAnalysisRules statUnitAnalysisRules, DbMandatoryFields mandatoryFields, ValidationSettings validationSettings, StatUnitTypeOfSave statUnitTypeOfSave)
        {
            _dbContext = dbContext;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _mandatoryFields = mandatoryFields;
            _userService = new UserService(dbContext);
            _commonSvc = new Common(dbContext);
            _validationSettings = validationSettings;
            _dataAccessService = new DataAccessService(dbContext);
            _statUnitTypeOfSave = statUnitTypeOfSave;
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
        /// Legal unit creation method
        /// </summary>
        /// <param name="data">Data</param>
        /// <param name="userId">User Id</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateLegalUnit(LegalUnitCreateM data, string userId)
            => await CreateUnitContext<LegalUnit, LegalUnitCreateM>(data, userId, unit =>
            {
                var helper = new StatUnitCheckPermissionsHelper(_dbContext);
                helper.CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, data.Activities.Select(x => x.ActivityCategoryId).ToList());

                if (Common.HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                {
                    if (data.LocalUnits != null && data.LocalUnits.Any())
                    {
                        var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                        foreach (var localUnit in localUnits)
                        {
                            unit.LocalUnits.Add(localUnit);
                        }
                        unit.HistoryLocalUnitIds = string.Join(",", data.LocalUnits);
                    }
                }
                return Task.CompletedTask;
            });

        /// <summary>
        /// Local unit creation method
        /// </summary>
        /// <param name="data">Data</param>
        /// <param name="userId">User Id</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateLocalUnit(LocalUnitCreateM data, string userId)
        {
            var helper = new StatUnitCheckPermissionsHelper(_dbContext);
            helper.CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, data.Activities.Select(x => x.ActivityCategoryId).ToList());

            return await CreateUnitContext<LocalUnit, LocalUnitCreateM>(data, userId, null);
        }

        /// <summary>
        /// Enterprise creation method
        /// </summary>
        /// <param name="data">Data</param>
        /// <param name="userId">User Id</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateEnterpriseUnit(EnterpriseUnitCreateM data, string userId)
            => await CreateUnitContext<EnterpriseUnit, EnterpriseUnitCreateM>(data, userId, unit =>
            {
                var helper = new StatUnitCheckPermissionsHelper(_dbContext);
                helper.CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, data.Activities.Select(x => x.ActivityCategoryId).ToList());
                if (data.LegalUnits != null && data.LegalUnits.Any())
                {
                    var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                    foreach (var legalUnit in legalUnits)
                    {
                        unit.LegalUnits.Add(legalUnit);
                    }
                    unit.HistoryLegalUnitIds = string.Join(",", data.LegalUnits);
                }
                   

                return Task.CompletedTask;
            });

        /// <summary>
        /// Method for creating an enterprise group
        /// </summary>
        /// <param name="data">Data</param>
        /// <param name="userId">User Id</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateEnterpriseGroup(EnterpriseGroupCreateM data, string userId)
            => await CreateContext<EnterpriseGroup, EnterpriseGroupCreateM>(data, userId, unit =>
            {
                var helper = new StatUnitCheckPermissionsHelper(_dbContext);
                helper.CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, new List<int>());

                if (Common.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                {
                    if (data.EnterpriseUnits != null && data.EnterpriseUnits.Any())
                    {
                        var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId))
                            .ToList();
                        foreach (var enterprise in enterprises)
                        {
                            unit.EnterpriseUnits.Add(enterprise);
                        }
                        unit.HistoryEnterpriseUnitIds = string.Join(",", data.EnterpriseUnits);
                    }
                }
                
                return Task.CompletedTask;
            });
        /// <summary>
        /// Static unit context creation method
        /// </summary>
        /// <param name="data">Data</param>
        /// <param name="userId">User Id</param>
        /// <param name="work">In work</param>
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
                    if (v.Id.HasValue && v.Id > 0)
                    {
                        return new PersonStatisticalUnit { PersonId = (int)v.Id, PersonTypeId = v.Role };
                    }
                    var newPerson = Mapper.Map<PersonM, Person>(v);
                    return new PersonStatisticalUnit { Person = newPerson, PersonTypeId = v.Role };
                }));

                var statUnits = data.PersonStatUnits ?? new List<PersonStatUnitModel>();
                foreach (var unitM in statUnits)
                {
                    unit.PersonsUnits.Add(new PersonStatisticalUnit
                    {
                        EnterpriseGroupId = unitM.StatRegId == null ? unitM.GroupRegId : null,
                        PersonId = null,
                        PersonTypeId = unitM.RoleId
                    });
                }

                var countriesList = data.ForeignParticipationCountriesUnits ?? new List<int>();

                unit.ForeignParticipationCountriesUnits.AddRange(countriesList.Select(v => new CountryStatisticalUnit { CountryId = v }));
                if (unit.SizeId == 0)
                {
                    unit.SizeId = null;
                }
                if (work != null)
                {
                    await work(unit);
                }
            });

        /// <summary>
        /// Context сreation method
        /// </summary>
        /// <param name="data">Data</param>
        /// <param name="userId">User Id</param>
        /// <param name="work">In Work</param>
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

            if (_statUnitTypeOfSave == StatUnitTypeOfSave.Service)
            {
                IStatUnitAnalyzeService analysisService = new AnalyzeService(_dbContext, _statUnitAnalysisRules, _mandatoryFields, _validationSettings);
                var analyzeResult = analysisService.AnalyzeStatUnit(unit, isSkipCustomCheck: true);
                if (analyzeResult.Messages.Any()) return analyzeResult.Messages;
            }

            var helper = new StatUnitCreationHelper(_dbContext);
            await helper.CheckElasticConnect();
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
