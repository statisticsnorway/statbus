using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Core;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using nscreg.Data.Extensions;
using nscreg.Resources.Languages;
using nscreg.Server.Models.Lookup;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Services
{
    public class StatUnitService
    {
        private readonly Dictionary<StatUnitTypes, Action<int, bool>> _deleteUndeleteActions;
        private readonly NSCRegDbContext _dbContext;
        private readonly ReadContext _readCtx;
        
        public StatUnitService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _readCtx = new ReadContext(dbContext);
            _deleteUndeleteActions = new Dictionary<StatUnitTypes, Action<int, bool>>
            {
                [StatUnitTypes.EnterpriseGroup] = DeleteUndeleteEnterpriseGroupUnit,
                [StatUnitTypes.EnterpriseUnit] = DeleteUndeleteEnterpriseUnit,
                [StatUnitTypes.LocalUnit] = DeleteUndeleteLocalUnit,
                [StatUnitTypes.LegalUnit] = DeleteUndeleteLegalUnit
            };
        }

        #region SEARCH

        public SearchVm Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            var propNames = GetDataAccessAttrs(userId);
            var unit =
                _readCtx.StatUnits
                    .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                    .Include(x => x.Address)
                    .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                    .Select(
                        x =>
                            new
                            {
                                x.RegId,
                                x.Name,
                                x.Address,
                                x.Turnover,
                                x.Employees,
                                UnitType =
                                x is LocalUnit
                                    ? StatUnitTypes.LocalUnit
                                    : x is LegalUnit ? StatUnitTypes.LegalUnit : StatUnitTypes.EnterpriseUnit
                            });
            var group =
                _readCtx.EnterpriseGroups
                    .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                    .Include(x => x.Address)
                    .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                    .Select(
                        x =>
                            new
                            {
                                x.RegId,
                                x.Name,
                                x.Address,
                                x.Turnover,
                                x.Employees,
                                UnitType = StatUnitTypes.EnterpriseGroup
                            });
            var filtered = unit.Concat(group);

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                Predicate<string> checkWildcard =
                    superStr => !string.IsNullOrEmpty(superStr) && superStr.Contains(query.Wildcard);
                filtered = filtered.Where(x =>
                    x.Name.Contains(query.Wildcard)
                    || x.Address != null
                    && (checkWildcard(x.Address.AddressPart1)
                        || checkWildcard(x.Address.AddressPart2)
                        || checkWildcard(x.Address.AddressPart3)
                        || checkWildcard(x.Address.AddressPart4)
                        || checkWildcard(x.Address.AddressPart5)
                        || checkWildcard(x.Address.GeographicalCodes)));
            }

            if (query.Type.HasValue)
                filtered = filtered.Where(x => x.UnitType == query.Type.Value);

            if (query.TurnoverFrom.HasValue)
                filtered = filtered.Where(x => x.Turnover >= query.TurnoverFrom);

            if (query.TurnoverTo.HasValue)
                filtered = filtered.Where(x => x.Turnover <= query.TurnoverTo);

            if (query.EmployeesNumberFrom.HasValue)
                filtered = filtered.Where(x => x.Employees >= query.EmployeesNumberFrom);

            if (query.EmployeesNumberTo.HasValue)
                filtered = filtered.Where(x => x.Employees <= query.EmployeesNumberTo);

            var total = filtered.Count();
            var totalPages = (int) Math.Ceiling((double) total / query.PageSize);
            var skip = query.PageSize * (Math.Min(totalPages, query.Page) - 1);

            var result = filtered
                .Skip(skip)
                .Take(query.PageSize)
                .Select(x => SearchItemVm.Create(x, x.UnitType, propNames))
                .ToList();

            return SearchVm.Create(result, total);
        }

        private HashSet<string> GetDataAccessAttrs(string userId)
            => new HashSet<string>(_dbContext.Users.Find(userId)?.DataAccessArray ?? Enumerable.Empty<string>());

        #endregion

        #region VIEW

        internal object GetUnitByIdAndType(int id, StatUnitTypes type, string userId)
        {
            var item = GetNotDeletedStatisticalUnitByIdAndType(id, type);
            return SearchItemVm.Create(item, item.UnitType, GetDataAccessAttrs(userId));
        }

        private IStatisticalUnit GetNotDeletedStatisticalUnitByIdAndType(int id, StatUnitTypes type)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                case StatUnitTypes.LegalUnit:
                    return _dbContext.StatisticalUnits
                        .Include(v => v.ActivitiesUnits)
                        .ThenInclude(v => v.Activity)
                        .ThenInclude(v => v.ActivityRevxCategory)
                        .Where(x => !x.IsDeleted)
                        .First(x => x.RegId == id);
                case StatUnitTypes.EnterpriseUnit:
                    return
                        _dbContext.EnterpriseUnits.Include(x => x.LocalUnits)
                            .Include(x => x.LegalUnits)
                            .Include(v => v.ActivitiesUnits)
                            .ThenInclude(v => v.Activity)
                            .ThenInclude(v => v.ActivityRevxCategory)
                            .Where(x => !x.IsDeleted)
                            .First(x => x.RegId == id);
                case StatUnitTypes.EnterpriseGroup:
                    return _dbContext.EnterpriseGroups
                        .Where(x => !x.IsDeleted)
                        .Include(x => x.EnterpriseUnits)
                        .First(x => x.RegId == id);
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        #endregion

        #region DELETE

        public void DeleteUndelete(StatUnitTypes unitType, int id, bool toDelete)
        {
            _deleteUndeleteActions[unitType](id, toDelete);
        }

        private void DeleteUndeleteEnterpriseGroupUnit(int id, bool toDelete)
        {
            var unit = _dbContext.EnterpriseGroups.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseGroup();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            _dbContext.EnterpriseGroups.Add((EnterpriseGroup) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteLegalUnit(int id, bool toDelete)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LegalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            _dbContext.LegalUnits.Add((LegalUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteLocalUnit(int id, bool toDelete)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LocalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            _dbContext.LocalUnits.Add((LocalUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteEnterpriseUnit(int id, bool toDelete)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            _dbContext.EnterpriseUnits.Add((EnterpriseUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        #endregion

        #region CREATE

        public async Task CreateLegalUnit(LegalUnitCreateM data, string userId)
        {
            await CreateContext<LegalUnit, LegalUnitCreateM>(data, userId, null);
        }

        public async Task CreateLocalUnit(LocalUnitCreateM data, string userId)
        {
            await CreateContext<LocalUnit, LocalUnitCreateM>(data, userId, null);
        }

        public async Task CreateEnterpriseUnit(EnterpriseUnitCreateM data, string userId)
        {
            await CreateContext<EnterpriseUnit, EnterpriseUnitCreateM>(data, userId, unit =>
            {
                var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId)).ToList();
                foreach (var localUnit in localUnits)
                {
                    unit.LocalUnits.Add(localUnit);
                }
                var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                foreach (var legalUnit in legalUnits)
                {
                    unit.LegalUnits.Add(legalUnit);
                }
            });
        }

        public void CreateEnterpriseGroupUnit(EnterpriseGroupCreateM data)
        {
            var unit = Mapper.Map<EnterpriseGroupCreateM, EnterpriseGroup>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<EnterpriseGroup>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            _dbContext.EnterpriseGroups.Add(unit);
            var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId)).ToList();
            foreach (var enterprise in enterprises)
            {
                unit.EnterpriseUnits.Add(enterprise);
            }
            var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
            foreach (var legalUnit in legalUnits)
            {
                unit.LegalUnits.Add(legalUnit);
            }
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.CreateEnterpriseGroupError), e);
            }
        }

        private async Task CreateContext<TUnit, TModel>(TModel data, string userId,
            Action<TUnit> work) where TModel : StatUnitModelBase where TUnit : StatisticalUnit, new()
        {
            var unit = Mapper.Map<TModel, TUnit>(data);
            AddAddresses(unit, data);

            if (!NameAddressIsUnique<TUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);

            var activitiesList = data.Activities ?? new List<ActivityM>();

            //Get Ids for codes
            var activityService = new CodeLookupService<ActivityCategory>(_dbContext);
            var codesList = activitiesList.Select(v => v.ActivityRevxCategory.Code).ToList();

            var codesLookup = new CodeLookupProvider<CodeLookupVm>(
                nameof(Resource.ActivityCategoryLookup),
                await activityService.List(false, v => codesList.Contains(v.Code))
            );

            unit.ActivitiesUnits.AddRange(activitiesList.Select(v =>
                {
                    var activity = Mapper.Map<ActivityM, Activity>(v);
                    activity.Id = 0;
                    activity.ActivityRevx = codesLookup.Get(activity.ActivityRevxCategory.Code).Id;
                    activity.UpdatedBy = userId;
                    return new ActivityStatisticalUnit {Activity = activity};
                }
            ));
            

            work?.Invoke(unit);

            _dbContext.Set<TUnit>().Add(unit);

            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        #endregion

        #region EDIT

        public async Task EditLegalUnit(LegalUnitEditM data, string userId)
        {
            await EditContext<LegalUnit, LegalUnitEditM>(data, m => m.RegId.Value, userId, null);
        }

        public async Task EditLocalUnit(LocalUnitEditM data, string userId)
        {
            await EditContext<LocalUnit, LocalUnitEditM>(data, v => v.RegId.Value, userId, null);
        }

        public async Task EditEnterpiseUnit(EnterpriseUnitEditM data, string userId)
        {
            await EditContext<EnterpriseUnit, EnterpriseUnitEditM>(data, m => m.RegId.Value, userId, unit =>
            {
                var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                foreach (var localUnit in localUnits)
                {
                    unit.LocalUnits.Add(localUnit);
                }
                var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId));
                foreach (var legalUnit in legalUnits)
                {
                    unit.LegalUnits.Add(legalUnit);
                }
            });
        }

        public void EditEnterpiseGroup(EnterpriseGroupEditM data)
        {
            var unit = (EnterpriseGroup) ValidateChanges<EnterpriseGroup>(data, data.RegId.Value);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            var hUnit = new EnterpriseGroup();
            Mapper.Map(unit, hUnit);
            Mapper.Map(data, unit);
            if (IsNoChanges(unit, hUnit)) return;
            AddAddresses(unit, data);
            _dbContext.EnterpriseGroups.Add((EnterpriseGroup) TrackHistory(unit, hUnit));
            var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId));
            unit.EnterpriseUnits.Clear();
            foreach (var enterprise in enterprises)
            {
                unit.EnterpriseUnits.Add(enterprise);
            }
            unit.LegalUnits.Clear();
            var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
            foreach (var legalUnit in legalUnits)
            {
                unit.LegalUnits.Add(legalUnit);
            }
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.UpdateEnterpriseGroupError), e);
            }
        }

        private async Task EditContext<TUnit, TModel>(TModel data, Func<TModel, int> idSelector, string userId,
            Action<TUnit> work) where TModel : StatUnitModelBase where TUnit : StatisticalUnit, new()
        {
            var unit = (TUnit) ValidateChanges<TUnit>(data, idSelector(data));
            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);
            Mapper.Map(data, unit);

            //Merge activities
            var activities = new List<ActivityStatisticalUnit>();
            var srcActivities = unit.ActivitiesUnits.ToDictionary(v => v.ActivityId);
            var activitiesList = data.Activities ?? new List<ActivityM>();
            
            //Get Ids for codes
            var activityService = new CodeLookupService<ActivityCategory>(_dbContext);
            var codesList = activitiesList.Select(v => v.ActivityRevxCategory.Code).ToList();

            var codesLookup = new CodeLookupProvider<CodeLookupVm>(
                nameof(Resource.ActivityCategoryLookup), 
                await activityService.List(false, v => codesList.Contains(v.Code))
            );

            foreach (var model in activitiesList)
            {
                ActivityStatisticalUnit activityAndUnit = null;

                if (model.Id.HasValue && srcActivities.TryGetValue(model.Id.Value, out activityAndUnit))
                {
                    var currentActivity = activityAndUnit.Activity;

                    if (model.ActivityRevxCategory.Id == currentActivity.ActivityRevx && ObjectComparer.SequentialEquals(model, currentActivity))
                    {
                        activities.Add(activityAndUnit);
                        continue;
                    }
                }
                var newActivity = new Activity();
                Mapper.Map(model, newActivity);
                newActivity.UpdatedBy = userId;
                newActivity.ActivityRevx = codesLookup.Get(model.ActivityRevxCategory.Code).Id;
                activities.Add(new ActivityStatisticalUnit() {Activity = newActivity});
            }
            var activitiesUnits = unit.ActivitiesUnits;
            activitiesUnits.Clear();
            unit.ActivitiesUnits.AddRange(activities);

            //External Mappings
            work?.Invoke(unit);

            if (IsNoChanges(unit, hUnit)) return;
            AddAddresses(unit, data);

            _dbContext.Set<TUnit>().Add((TUnit) TrackHistory(unit, hUnit));

            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                //TODO: Processing Validation Errors
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        #endregion

        private void AddAddresses(IStatisticalUnit unit, IStatUnitM data)
        {
            if (data.Address != null && !data.Address.IsEmpty())
                unit.Address = GetAddress(data.Address);
            else unit.Address = null;
            if (data.ActualAddress != null && !data.ActualAddress.IsEmpty())
                unit.ActualAddress = data.ActualAddress.Equals(data.Address)
                    ? unit.Address
                    : GetAddress(data.ActualAddress);
            else unit.ActualAddress = null;
        }

        private Address GetAddress(AddressM data)
        {
            return _dbContext.Address.SingleOrDefault(a
                       => a.Id == data.Id &&
                          a.AddressDetails == data.AddressDetails &&
                          a.GpsCoordinates == data.GpsCoordinates &&
                          a.GeographicalCodes == data.GeographicalCodes) //Check unique fields only
                   ?? new Address()
                   {
                       AddressPart1 = data.AddressPart1,
                       AddressPart2 = data.AddressPart2,
                       AddressPart3 = data.AddressPart3,
                       AddressPart4 = data.AddressPart4,
                       AddressPart5 = data.AddressPart5,
                       AddressDetails = data.AddressDetails,
                       GeographicalCodes = data.GeographicalCodes,
                       GpsCoordinates = data.GpsCoordinates
                   };
        }

        private bool NameAddressIsUnique<T>(string name, AddressM address, AddressM actualAddress)
            where T : class, IStatisticalUnit
        {
            if (address == null) address = new AddressM();
            if (actualAddress == null) actualAddress = new AddressM();
            var units =
                _dbContext.Set<T>()
                    .Include(a => a.Address)
                    .Include(aa => aa.ActualAddress)
                    .Where(u => u.Name == name)
                    .ToList();
            return
                units.All(
                    unit =>
                        !address.Equals(unit.Address) && !actualAddress.Equals(unit.ActualAddress));
        }

        private IStatisticalUnit ValidateChanges<T>(IStatUnitM data, int regid)
            where T : class, IStatisticalUnit
        {
            var unit = GetNotDeletedStatisticalUnitByIdAndType(regid, StatisticalUnitsExtensions.GetStatUnitMappingType(typeof(T)));

            if (!unit.Name.Equals(data.Name) &&
                !NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            else if (data.Address != null && data.ActualAddress != null && !data.Address.Equals(unit.Address) &&
                     !data.ActualAddress.Equals(unit.ActualAddress) &&
                     !NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            else if (data.Address != null && !data.Address.Equals(unit.Address) &&
                     !NameAddressIsUnique<T>(data.Name, data.Address, null))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            else if (data.ActualAddress != null && !data.ActualAddress.Equals(unit.ActualAddress) &&
                     !NameAddressIsUnique<T>(data.Name, null, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);

            return unit;
        }
        
        private bool IsNoChanges(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var unitType = unit.GetType();
            var propertyInfo = unitType.GetProperties();
            foreach (var property in propertyInfo)
            {
                var unitProperty = unitType.GetProperty(property.Name).GetValue(unit, null);
                var hUnitProperty = unitType.GetProperty(property.Name).GetValue(hUnit, null);
                if (!Equals(unitProperty, hUnitProperty)) return false;
            }
            var statUnit = unit as StatisticalUnit;
            if (statUnit != null)
            {
                var hstatUnit = (StatisticalUnit) hUnit;
                if (!hstatUnit.ActivitiesUnits.CompareWith(statUnit.ActivitiesUnits, v => v.ActivityId))
                {
                    return false;
                }
            }
            return true;
        }

        private IStatisticalUnit TrackHistory(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var timeStamp = DateTime.Now;
            unit.StartPeriod = timeStamp;
            hUnit.RegId = 0;
            hUnit.EndPeriod = timeStamp;
            hUnit.ParrentId = unit.RegId;
            return hUnit;
        }

        public IEnumerable<LookupVm> GetEnterpriseUnitsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.EnterpriseUnits);

        public IEnumerable<LookupVm> GetEnterpriseGroupsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.EnterpriseGroups);

        public IEnumerable<LookupVm> GetLegalUnitsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.LegalUnits);

        public IEnumerable<LookupVm> GetLocallUnitsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.LocalUnits);

        public StatUnitViewModel GetViewModel(int? id, StatUnitTypes type, string userId)
        {
            var item = id.HasValue
                ? GetNotDeletedStatisticalUnitByIdAndType(id.Value, type)
                : GetDefaultDomainForType(type);
            var creator = new StatUnitViewModelCreator();
            return (StatUnitViewModel)creator.Create(item, GetDataAccessAttrs(userId));
        }

        private IStatisticalUnit GetDefaultDomainForType(StatUnitTypes type)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return new LocalUnit();
                case StatUnitTypes.LegalUnit:
                    return new LegalUnit();
                case StatUnitTypes.EnterpriseUnit:
                    return new EnterpriseUnit();
                case StatUnitTypes.EnterpriseGroup:
                    return new EnterpriseGroup();
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        } 
    }
}
