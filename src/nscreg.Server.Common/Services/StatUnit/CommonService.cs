using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Data.Entities.History;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Utilities;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Server.Common.Services.Contracts;
using Microsoft.AspNetCore.Mvc.ViewFeatures;

namespace nscreg.Server.Common.Services.StatUnit
{
    internal static class CommonExtensions
    {
        public static IQueryable<T> IncludeCommonFields<T>(this IQueryable<T> query) where T : class, IStatisticalUnit
        {
            return query.Include(v => v.ActualAddress)
                .ThenInclude(a => a.Region)
                .Include(v => v.PostalAddress)
                .ThenInclude(a => a.Region)
                .Include(v => v.PersonsUnits) // PersonsUnit.Unit is implicitly included by EF.
                .Include(v => v.PersonsUnits)
                .ThenInclude(v => v.EnterpriseGroup);
        }

        public static IQueryable<T> IncludeAdvancedFields<T>(this IQueryable<T> query) where T : class, IStatisticalUnit
        {
            return query.IncludeCommonFields()
                .Include(v => v.PersonsUnits)
                .ThenInclude(v => v.Person)
                .Include(v => v.ActivitiesUnits)
                .ThenInclude(v => v.Activity)
                .ThenInclude(v => v.ActivityCategory)
                .Include(v => v.ForeignParticipationCountriesUnits);
        }
    }

    /// <summary>
    /// Common service stat units
    /// </summary>
    public class CommonService
    {
        private readonly NSCRegDbContext _dbContext;
        private bool IsBulk => _buffer != null;
        private readonly UpsertUnitBulkBuffer _buffer;
        private readonly IMapper _mapper;
        //private readonly IUserService _userService;

        public CommonService(NSCRegDbContext dbContext, IMapper mapper,
            /*IUserService userService,*/ UpsertUnitBulkBuffer buffer = null)
        {
            _buffer = buffer;
            _dbContext = dbContext;
            _mapper = mapper;
            //_userService = userService;
        }

        public static readonly Expression<Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>>> UnitMapping =
            u => Tuple.Create(
                new CodeLookupVm {Id = u.RegId, Code = u.StatId, Name = u.Name},
                u.GetType());

        private static readonly Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>> UnitMappingFunc =
            UnitMapping.Compile();

        /// <summary>
        /// Method for getting stat. units by Id and type
        /// </summary>
        /// <param name="id">Stat Id</param>
        /// <param name="type"></param>
        /// <param name="showDeleted">Remoteness flag</param>
        /// <returns></returns>
        public async Task<IStatisticalUnit> GetStatisticalUnitByIdAndType(int id, StatUnitTypes type, bool showDeleted)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return await GetUnitById<StatisticalUnit>(id, showDeleted, query => query.IncludeAdvancedFields());
                case StatUnitTypes.LegalUnit:
                    return await GetUnitById<LegalUnit>(id, showDeleted, query => query.IncludeAdvancedFields().Include(x => x.LocalUnits).Include(y => y.LegalForm));
                case StatUnitTypes.EnterpriseUnit:
                    return await GetUnitById<EnterpriseUnit>(id, showDeleted, query => query.IncludeAdvancedFields().Include(x => x.LegalUnits));
                case StatUnitTypes.EnterpriseGroup:
                    return await GetUnitById<EnterpriseGroup>(id, showDeleted, query => query.IncludeCommonFields().Include(x => x.EnterpriseUnits));
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        /// <summary>
        /// Method for obtaining a sp stat. units
        /// </summary>
        /// <param name="showDeleted">Remoteness flag</param>
        /// <returns></returns>
        public IQueryable<T> GetUnitsList<T>(bool showDeleted) where T : class, IStatisticalUnit
        {
            var query = _dbContext.Set<T>().AsQueryable();
            if (!showDeleted) query = query.Where(v => !v.IsDeleted);
            return query;
        }

        /// <summary>
        /// Method for getting stat. units by id
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="showDeleted">Remoteness flag</param>
        /// <param name="work">In work</param>
        /// <returns></returns>
        public async Task<T> GetUnitById<T>( int id, bool showDeleted,
            Func<IQueryable<T>, IQueryable<T>> work = null) where T : class, IStatisticalUnit
        {
            var query = GetUnitsList<T>(showDeleted);
            if (work != null) query = work(query);
            var unitById = await query.AsSplitQuery().SingleOrDefaultAsync(v => v.RegId == id);
            return unitById;
        }

        /// <summary>
        /// Method for tracking related stories stat. units
        /// </summary>
        /// <param name="unit">Stat. unit</param>
        /// <param name="hUnit">History stat. units</param>
        /// <param name="userId">User Id</param>
        /// <param name="changeReason">Reason for change</param>
        /// <param name="comment">Comment</param>
        /// <param name="changeDateTime">Change Date</param>
        /// <param name="unitsHistoryHolder">Keeper of the history stat. units</param>
        public void TrackRelatedUnitsHistory<TUnit>(
            TUnit unit,
            TUnit hUnit,
            string userId,
            ChangeReasons changeReason,
            string comment,
            DateTime changeDateTime,
            UnitsHistoryHolder unitsHistoryHolder)
            where TUnit : class, IStatisticalUnit, new()
        {
            switch (unit.GetType().Name)
            {
                case nameof(LocalUnit):
                {
                    var localUnit = unit as LocalUnit;

                    if (localUnit?.LegalUnitId != unitsHistoryHolder.HistoryUnits.legalUnitId)
                    {
                        void PostAction(IStatisticalUnit historyUnit, IStatisticalUnit editedUnit)
                        {
                            var legalUnit = editedUnit as LegalUnit;
                            if (legalUnit != null && string.IsNullOrEmpty(legalUnit.HistoryLocalUnitIds))
                                return;
                            var historyLocalUnits = legalUnit?.HistoryLocalUnitIds?.Split(',')
                                .Select(int.Parse)
                                .ToList();
                            if (historyLocalUnits == null) return;
                            if (localUnit != null && historyLocalUnits.Contains(localUnit.RegId) &&
                                legalUnit.RegId != localUnit.LegalUnitId)
                            {
                                historyLocalUnits.Remove(localUnit.RegId);
                            }
                            else if (localUnit != null && !historyLocalUnits.Contains(localUnit.RegId))
                            {
                                historyLocalUnits.Add(localUnit.RegId);
                            }
                            legalUnit.HistoryLocalUnitIds = historyLocalUnits.Count == 0
                                ? null
                                : string.Join(",", historyLocalUnits);
                        }

                        TrackUnitHistoryFor<LegalUnit>(localUnit?.LegalUnitId, userId, changeReason, comment,
                            changeDateTime, PostAction);
                        TrackUnitHistoryFor<LegalUnit>(unitsHistoryHolder.HistoryUnits.legalUnitId, userId,
                            changeReason, comment, changeDateTime, PostAction);
                    }

                    break;
                }

                case nameof(LegalUnit):
                {
                    var legalUnit = unit as LegalUnit;

                    TrackHistoryForListOfUnitsFor<LocalUnit>(
                        () => legalUnit?.LocalUnits.Select(x => x.RegId).ToList(),
                        () => unitsHistoryHolder.HistoryUnits.localUnitsIds,
                        userId,
                        changeReason,
                        comment,
                        changeDateTime,
                        (historyUnit, editedUnit) =>
                        {
                            if (!(historyUnit is LocalUnit hLocalUnit)) return;
                            if (unitsHistoryHolder.HistoryUnits.localUnitsIds.Count == 0)
                            {
                                hLocalUnit.LegalUnit = null;
                                hLocalUnit.LegalUnitId = null;
                                return;
                            }

                            if (editedUnit is LocalUnit editedLocalUnit
                                && !unitsHistoryHolder.HistoryUnits.localUnitsIds.Contains(editedLocalUnit.RegId)
                                && editedLocalUnit.LegalUnitId != null)
                            {
                                hLocalUnit.LegalUnit = null;
                                hLocalUnit.LegalUnitId = null;
                                return;
                            }

                            hLocalUnit.LegalUnit = legalUnit;
                            if (legalUnit != null) hLocalUnit.LegalUnitId = legalUnit.RegId;
                        });

                    if (legalUnit?.EnterpriseUnitRegId != unitsHistoryHolder.HistoryUnits.enterpriseUnitId)
                    {
                        void PostAction(IStatisticalUnit historyUnit, IStatisticalUnit editedUnit)
                        {
                            var enterpriseUnit = editedUnit as EnterpriseUnit;
                            if (enterpriseUnit != null && string.IsNullOrEmpty(enterpriseUnit.HistoryLegalUnitIds))
                                return;
                            var historyLegalUnits = enterpriseUnit?.HistoryLegalUnitIds?.Split(',').Select(int.Parse)
                                .ToList();
                            if (historyLegalUnits == null) return;
                            if (legalUnit != null && (historyLegalUnits.Contains(legalUnit.RegId) &&
                                                      enterpriseUnit.RegId != legalUnit.EnterpriseUnitRegId))
                            {
                                historyLegalUnits.Remove(legalUnit.RegId);
                            }
                            else if (legalUnit != null && !historyLegalUnits.Contains(legalUnit.RegId))
                            {
                                historyLegalUnits.Add(legalUnit.RegId);
                            }
                            enterpriseUnit.HistoryLegalUnitIds = string.Join(",", historyLegalUnits);
                        }

                        TrackUnitHistoryFor<EnterpriseUnit>(legalUnit?.EnterpriseUnitRegId, userId, changeReason,
                            comment, changeDateTime, PostAction);
                        TrackUnitHistoryFor<EnterpriseUnit>(unitsHistoryHolder.HistoryUnits.enterpriseUnitId, userId,
                            changeReason, comment, changeDateTime, PostAction);
                    }

                    break;
                }

                case nameof(EnterpriseUnit):
                {
                    var enterpriseUnit = unit as EnterpriseUnit;

                    TrackHistoryForListOfUnitsFor<LegalUnit>(
                        () => enterpriseUnit?.LegalUnits.Select(x => x.RegId).ToList(),
                        () => unitsHistoryHolder.HistoryUnits.legalUnitsIds,
                        userId,
                        changeReason,
                        comment,
                        changeDateTime,
                        (historyUnit, editedUnit) =>
                        {
                            if (!(historyUnit is LegalUnit hlegalUnit)) return;
                            if (unitsHistoryHolder.HistoryUnits.legalUnitsIds.Count == 0)
                            {
                                hlegalUnit.EnterpriseUnit = null;
                                hlegalUnit.EnterpriseUnitRegId = null;
                                return;
                            }

                            if (editedUnit is LegalUnit editedLegalUnit
                                && !unitsHistoryHolder.HistoryUnits.legalUnitsIds.Contains(editedLegalUnit.RegId)
                                && editedLegalUnit.EnterpriseUnitRegId != null)
                            {
                                hlegalUnit.EnterpriseUnit = null;
                                hlegalUnit.EnterpriseUnitRegId = null;
                                return;
                            }

                            hlegalUnit.EnterpriseUnit = enterpriseUnit;
                            if (enterpriseUnit != null) hlegalUnit.EnterpriseUnitRegId = enterpriseUnit.RegId;
                        });

                    if (enterpriseUnit?.EntGroupId != unitsHistoryHolder.HistoryUnits.enterpriseGroupId)
                    {
                        void PostAction(IStatisticalUnit historyUnit, IStatisticalUnit editedUnit)
                        {
                            var enterpriseGroup = editedUnit as EnterpriseGroup;
                            if (enterpriseGroup != null &&
                                string.IsNullOrEmpty(enterpriseGroup.HistoryEnterpriseUnitIds))
                                return;
                            var historyEnterpriseUnits = enterpriseGroup?.HistoryEnterpriseUnitIds?.Split(',')
                                .Select(int.Parse).ToList();
                            if (historyEnterpriseUnits == null) return;
                            if (enterpriseUnit != null &&
                                (historyEnterpriseUnits.Contains(enterpriseUnit.RegId) &&
                                 enterpriseGroup.RegId != enterpriseUnit.EntGroupId))
                            {
                                historyEnterpriseUnits.Remove(enterpriseUnit.RegId);
                            }
                            else if (enterpriseUnit != null &&
                                     !historyEnterpriseUnits.Contains(enterpriseUnit.RegId))
                            {
                                historyEnterpriseUnits.Add(enterpriseUnit.RegId);
                            }
                            enterpriseGroup.HistoryEnterpriseUnitIds = string.Join(",", historyEnterpriseUnits);
                        }

                        TrackUnitHistoryFor<EnterpriseGroup>(enterpriseUnit?.EntGroupId, userId, changeReason, comment,
                            changeDateTime, PostAction);
                        TrackUnitHistoryFor<EnterpriseGroup>(unitsHistoryHolder.HistoryUnits.enterpriseGroupId, userId,
                            changeReason, comment, changeDateTime, PostAction);
                    }

                    break;
                }

                case nameof(EnterpriseGroup):
                {
                    var enterpriseGroup = unit as EnterpriseGroup;

                    TrackHistoryForListOfUnitsFor<EnterpriseUnit>(
                        () => enterpriseGroup?.EnterpriseUnits.Select(x => x.RegId)
                            .ToList(),
                        () => unitsHistoryHolder.HistoryUnits.enterpriseUnitsIds,
                        userId,
                        changeReason,
                        comment,
                        changeDateTime,
                        (historyUnit, editedUnit) =>
                        {
                            if (!(historyUnit is EnterpriseUnit hEnterpriseUnit)) return;
                            if (unitsHistoryHolder.HistoryUnits.enterpriseUnitsIds.Count == 0)
                            {
                                hEnterpriseUnit.EnterpriseGroup = null;
                                hEnterpriseUnit.EntGroupId = null;
                                return;
                            }

                            if (editedUnit is EnterpriseUnit editedEnterpriseUnit
                                && !unitsHistoryHolder.HistoryUnits.enterpriseUnitsIds.Contains(editedEnterpriseUnit
                                    .RegId)
                                && editedEnterpriseUnit.EntGroupId != null)
                            {
                                hEnterpriseUnit.EnterpriseGroup = null;
                                hEnterpriseUnit.EntGroupId = null;
                                return;
                            }

                            hEnterpriseUnit.EnterpriseGroup = enterpriseGroup;
                            if (enterpriseGroup != null) hEnterpriseUnit.EntGroupId = enterpriseGroup.RegId;
                        });
                    break;
                }

                default:
                    throw new NotImplementedException();
            }
        }

        /// <summary>
        /// List history tracking method for stat. units
        /// </summary>
        /// <param name="unitIdsSelector"></param>
        /// <param name="hUnitIdsSelector"></param>
        /// <param name="userId">User Id</param>
        /// <param name="changeReason">Reason for change</param>
        /// <param name="comment">Comment</param>
        /// <param name="changeDateTime">Change Date</param>
        /// <param name="work">In work</param>
        /// <param name="isBulk">Flag for bulk</param>
        /// <param name="buffer">Bulk Buffer</param>
        private void TrackHistoryForListOfUnitsFor<TUnit>(
            Func<List<int>> unitIdsSelector,
            Func<List<int>> hUnitIdsSelector,
            string userId,
            ChangeReasons changeReason,
            string comment,
            DateTime changeDateTime,
            Action<IStatisticalUnit, IStatisticalUnit> work = null, bool isBulk = false, UpsertUnitBulkBuffer buffer = null)
            where TUnit : class, IStatisticalUnit, new()
        {
            var unitIds = unitIdsSelector();
            var hUnitIds = hUnitIdsSelector();

            if (unitIds.SequenceEqual(hUnitIds)) return;

            foreach (var changeTrackingUnitId in unitIds.Union(hUnitIds).Except(unitIds.Intersect(hUnitIds)))
                TrackUnitHistoryFor<TUnit>(changeTrackingUnitId, userId, changeReason, comment, changeDateTime, work);
        }

        /// <summary>
        /// Stat history tracking method. units
        /// </summary>
        /// <param name="unitId">Stat unit Id</param>
        /// <param name="userId">User Id</param>
        /// <param name="changeReason">Change for reason</param>
        /// <param name="comment">Comment</param>
        /// <param name="changeDateTime">Change Date</param>
        /// <param name="work">In Work</param>
        /// <param name="isBulk">Bulk flag</param>
        /// <param name="buffer">Buffer</param>
        public void TrackUnitHistoryFor<TUnit>(
            int? unitId,
            string userId,
            ChangeReasons changeReason,
            string comment,
            DateTime changeDateTime,
            Action<IStatisticalUnit, IStatisticalUnit> work = null)
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = _dbContext.Set<TUnit>().SingleOrDefault(x => x.RegId == unitId);
            if (unit == null) return;

            var hUnit = new TUnit();
            _mapper.Map(unit, hUnit);
            hUnit.RegId = 0;
            work?.Invoke(hUnit, unit);

            unit.UserId = userId;
            unit.ChangeReason = changeReason;
            unit.EditComment = comment;
            var mappedHistoryUnit = MapUnitToHistoryUnit(hUnit);
            AddHistoryUnitByType(TrackHistory(unit, mappedHistoryUnit, changeDateTime));
        }

        /// <summary>
        /// History tracking method
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <param name="hUnit">Stat unit history</param>
        /// <param name="changeDateTime">Change Date</param>
        /// <returns></returns>
        public static IStatisticalUnitHistory TrackHistory(
            IStatisticalUnit unit,
            IStatisticalUnitHistory hUnit,
            DateTime? changeDateTime = null)
        {
            var timeStamp = changeDateTime ?? DateTime.Now;
            unit.StartPeriod = timeStamp;
            hUnit.RegId = 0;
            hUnit.EndPeriod = timeStamp;
            hUnit.ParentId = unit.RegId;
            return hUnit;
        }

        /// <summary>
        /// Data Access Attribute Initialization Method
        /// </summary>
        /// <param name="userService">user service</param>
        /// <param name="data">data</param>
        /// <param name="userId">user Id</param>
        /// <param name="type">type</param>
        /// <returns></returns>
        public async Task<DataAccessPermissions> InitializeDataAccessAttributes<TModel>(
            UserService userService,
            TModel data,
            string userId,
            StatUnitTypes type) where TModel: IStatUnitM
        {
            var dataAccess = data?.DataAccess ?? new DataAccessPermissions();
            var userDataAccess = await userService.GetDataAccessAttributes(userId, type);
            var dataAccessChanged = !dataAccess.IsEqualTo(userDataAccess);
            if (dataAccessChanged)
            {
                throw new BadRequestException(nameof(Resource.DataAccessConflict));
            }
            if (data != null)
            {
                data.DataAccess = dataAccess;
                return dataAccess;
            }
            return userDataAccess;
        }

        /// <summary>
        /// Access Definition Method
        /// </summary>
        /// <param name="dataAccess">data access</param>
        /// <param name="property">property</param>
        /// <returns></returns>
        public static bool HasAccess<T>(DataAccessPermissions dataAccess, Expression<Func<T, object>> property) =>
            dataAccess.HasWritePermission(
                DataAccessAttributesHelper.GetName<T>(ExpressionUtils.GetExpressionText<T>(property)));

        /// <summary>
        /// Add Address Method
        /// </summary>
        /// <param name="unit">stat unit</param>
        /// <param name="data">data</param>
        public async Task AddAddresses<TUnit>(IStatisticalUnit unit, IStatUnitM data) where TUnit : IStatisticalUnit
        {
            if (data.ActualAddress != null && !data.ActualAddress.IsEmpty() &&
                HasAccess<TUnit>(data.DataAccess, v => v.ActualAddress))
                unit.ActualAddress = await GetAddress(data.ActualAddress);
            else unit.ActualAddress = null;
            if (data.PostalAddress != null && !data.PostalAddress.IsEmpty() &&
                HasAccess<TUnit>(data.DataAccess, v => v.PostalAddress))
                unit.PostalAddress = await GetAddress(data.PostalAddress);
            else unit.PostalAddress = null;
        }

        /// <summary>
        /// Address Name Uniqueness Method
        /// </summary>
        /// <param name="name">Name</param>
        /// <param name="address">Address</param>
        /// <param name="actualAddress">Actual address</param>
        /// <returns></returns>
        public bool NameAddressIsUnique<T>(
            string name,
            AddressM address,
            AddressM actualAddress,
            AddressM postalAddress)
            where T : class, IStatisticalUnit
        {
            if (address == null) address = new AddressM();
            if (actualAddress == null) actualAddress = new AddressM();
            if(postalAddress == null) postalAddress = new AddressM();
            return _dbContext.Set<T>()
                .Include(aa => aa.ActualAddress)
                .Include(pa => pa.PostalAddress)
                .Where(u => u.Name == name)
                .All(unit => !actualAddress.Equals(unit.ActualAddress) && !postalAddress.Equals(unit.PostalAddress));
        }

        public T ToUnitLookupVm<T>(IStatisticalUnit unit) where T : UnitLookupVm, new()
            => ToUnitLookupVm<T>(UnitMappingFunc(unit));

        public IEnumerable<UnitLookupVm> ToUnitLookupVm(IEnumerable<Tuple<CodeLookupVm, Type>> source)
            => source.Select(ToUnitLookupVm<UnitLookupVm>);

        /// <summary>
        /// Stat conversion method. units in the model view reference
        /// </summary>
        /// <param name="unit">stat unit</param>
        /// <returns></returns>
        private T ToUnitLookupVm<T>(Tuple<CodeLookupVm, Type> unit) where T : UnitLookupVm, new()
        {
            var vm = new T
            {
                Type = StatisticalUnitsTypeHelper.GetStatUnitMappingType(unit.Item2)
            };
            _mapper.Map<CodeLookupVm, UnitLookupVm>(unit.Item1, vm);
            return vm;
        }

        /// <summary>
        /// Method of getting the address
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        private async Task<Address> GetAddress(AddressM data)
        {
            var address = await _dbContext.Address.FirstOrDefaultAsync(a =>
                  a.Id == data.Id &&
                  a.AddressPart1 == data.AddressPart1 &&
                  a.AddressPart2 == data.AddressPart2 &&
                  a.AddressPart3 == data.AddressPart3 &&
                  a.Region.Id == data.RegionId &&
                  a.Latitude == data.Latitude &&
                  a.Longitude == data.Longitude);
            if (address == null)
            {
                var region = await _dbContext.Regions.FirstOrDefaultAsync(r => r.Id == data.RegionId);
                if(region == null)
                {
                    throw new BadRequestException(nameof(Resource.RegionNotExistsError));
                }
                address = new Address
                {
                    AddressPart1 = data.AddressPart1,
                    AddressPart2 = data.AddressPart2,
                    AddressPart3 = data.AddressPart3,
                    Region = region,
                    RegionId = region.Id,
                    Latitude = data.Latitude,
                    Longitude = data.Longitude
                };
            }
            return address;

        }


        public IStatisticalUnitHistory MapUnitToHistoryUnit(IStatisticalUnit unit)
        {
            IStatisticalUnitHistory hUnit;

            switch (unit)
            {
                case LocalUnit _: hUnit = new LocalUnitHistory();
                    break;
                case LegalUnit _: hUnit = new LegalUnitHistory();
                    break;
                case EnterpriseUnit _: hUnit = new EnterpriseUnitHistory();
                    break;
                default: hUnit = new EnterpriseGroupHistory();
                    break;
            }

            _mapper.Map(unit, hUnit);
            return hUnit;
        }

        public IStatisticalUnit MapHistoryUnitToUnit(IStatisticalUnitHistory hUnit)
        {
            IStatisticalUnit unit;

            switch (hUnit)
            {
                case LocalUnitHistory _:
                    unit = new LocalUnit();
                    break;
                case LegalUnitHistory _:
                    unit = new LegalUnit();
                    break;
                case EnterpriseUnitHistory _:
                    unit = new EnterpriseUnit();
                    break;
                default:
                    unit = new EnterpriseGroup();
                    break;
            }

            _mapper.Map(hUnit, unit);
            return unit;
        }

        public void AddHistoryUnitByType(IStatisticalUnitHistory hUnit)
        {
            switch (hUnit)
            {
                case LocalUnitHistory locU:
                    if (IsBulk)
                    {
                        _buffer.AddToHistoryBuffer(locU);
                        break;
                    }
                    _dbContext.Set<LocalUnitHistory>().Add(locU);
                    break;
                case LegalUnitHistory legU:
                    if (IsBulk)
                    {
                        _buffer.AddToHistoryBuffer(legU);
                        break;
                    }
                    _dbContext.Set<LegalUnitHistory>().Add(legU);
                    break;
                case EnterpriseUnitHistory eu:
                    if (IsBulk)
                    {
                        _buffer.AddToHistoryBuffer(eu);
                        break;
                    }
                    _dbContext.Set<EnterpriseUnitHistory>().Add(eu);
                    break;
                default:
                    if (IsBulk)
                    {
                        _buffer.AddToHistoryBuffer(hUnit);
                        break;
                    }
                    _dbContext.Set<EnterpriseGroupHistory>().Add((EnterpriseGroupHistory) hUnit);
                    break;
            }
        }
    }
}
