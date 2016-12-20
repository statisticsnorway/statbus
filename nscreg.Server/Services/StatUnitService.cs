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
using nscreg.Resources.Languages;

namespace nscreg.Server.Services
{
    public class StatUnitService
    {
        private readonly Dictionary<Type, Action<IStatisticalUnit, bool>> _deleteUndeleteActions;
        private readonly NSCRegDbContext _dbContext;
        private readonly ReadContext _readCtx;

        public StatUnitService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _readCtx = new ReadContext(dbContext);
            _deleteUndeleteActions = new Dictionary<Type, Action<IStatisticalUnit, bool>>
            {
                {typeof(EnterpriseGroup), DeleteUndeleteEnterpriseGroupUnit},
                {typeof(EnterpriseUnit), DeleteUndeleteEnterpriseUnits},
                {typeof(LocalUnit), DeleteUndeleteLocalUnits},
                {typeof(LegalUnit), DeleteUndeleteLegalUnits}
            };
        }

        #region SEARCH

        public SearchVm Search(SearchQueryM query, IEnumerable<string> propNames)
        {
            var filtered = _readCtx.StatUnits.Where(x => (query.IncludeLiquidated || x.LiqDate == null));

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                Predicate<string> checkWildcard = superStr => !string.IsNullOrEmpty(superStr) && superStr.Contains(query.Wildcard);
                filtered = filtered.Where(x =>
                    x.Name.Contains(query.Wildcard)
                    || checkWildcard(x.Address.AddressPart1)
                    || checkWildcard(x.Address.AddressPart2)
                    || checkWildcard(x.Address.AddressPart3)
                    || checkWildcard(x.Address.AddressPart4)
                    || checkWildcard(x.Address.AddressPart5)
                    || checkWildcard(x.Address.GeographicalCodes));
            }

            if (query.Type.HasValue)
            {
                Func<StatisticalUnit, bool> checkType = GetCheckTypeClosure(query.Type.Value);
                filtered = filtered.Where(x => checkType(x));
            }

            if (query.TurnoverFrom.HasValue)
                filtered = filtered.Where(x => x.Turnover > query.TurnoverFrom);

            if (query.TurnoverTo.HasValue)
                filtered = filtered.Where(x => x.Turnover < query.TurnoverTo);

            var ids = filtered.Select(x => x.RegId);

            var resultGroup = ids
                .Skip(query.PageSize * query.Page)
                .Take(query.PageSize)
                .GroupBy(p => new { Total = ids.Count() })
                .FirstOrDefault();

            var total = resultGroup?.Key.Total ?? 0;

            return SearchVm.Create(
                resultGroup != null
                    ? StatUnitsToObjectsWithType(resultGroup, propNames)
                    : Array.Empty<object>(),
                total,
                (int)Math.Ceiling((double)total / query.PageSize));
        }

        private IEnumerable<object> StatUnitsToObjectsWithType(IEnumerable<int> statUnitIds, IEnumerable<string> propNames)
        {
            Func<StatUnitTypes, Func<object, object>> serialize = type => unit => SearchItemVm.Create(unit, type, propNames);
            return _readCtx.LocalUnits.Where(lo => statUnitIds.Any(id => lo.RegId == id)).Select(serialize(StatUnitTypes.LocalUnit))
                .Concat(_readCtx.LegalUnits.Where(le => statUnitIds.Any(id => le.RegId == id)).Select(serialize(StatUnitTypes.LegalUnit)))
                    .Concat(_readCtx.EnterpriseUnits.Where(en => statUnitIds.Any(id => en.RegId == id)).Select(serialize(StatUnitTypes.EnterpriseUnit)));
        }

        private Func<StatisticalUnit, bool> GetCheckTypeClosure(StatUnitTypes type)
        {
            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    return x => x is LegalUnit;
                case StatUnitTypes.LocalUnit:
                    return x => x is LocalUnit;
                case StatUnitTypes.EnterpriseUnit:
                    return x => x is EnterpriseUnit;
                case StatUnitTypes.EnterpriseGroup:
                    throw new NotImplementedException(nameof(Resource.EnterpriseGroupNotSupportError));
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), nameof(Resource.UnknownStatUnitTypeError));
            }
        }

        #endregion

        #region VIEW

        public IStatisticalUnit GetUnitById(StatUnitTypes unitType, int id)
        {
            IStatisticalUnit unit;
            try
            {
                unit = GetNotDeletedStatisticalUnitById(unitType, id);
            }
            catch (NotFoundException ex)
            {
                throw new NotFoundException(ex.Message);
            }
            return unit;
        }

        private IStatisticalUnit GetStatisticalUnitById(StatUnitTypes unitType, int id)
        {
            switch (unitType)
            {
                case StatUnitTypes.LegalUnit:
                    return _readCtx.LegalUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.LocalUnit:
                    return _readCtx.LocalUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseUnit:
                    return _readCtx.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseGroup:
                    return _readCtx.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
            }

            throw new NotFoundException(nameof(Resource.StatisticalUnitNotExistError));
        }

        private IStatisticalUnit GetNotDeletedStatisticalUnitById(StatUnitTypes unitType, int id)
        {
            switch (unitType)
            {
                case StatUnitTypes.LegalUnit:
                    return _readCtx.LegalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.LocalUnit:
                    return _readCtx.LocalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseUnit:
                    return _readCtx.EnterpriseUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseGroup:
                    return _readCtx.EnterpriseGroups.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
            }

            throw new NotFoundException(nameof(Resource.StatisticalUnitNotExistError));
        }

        #endregion

        #region DELETE

        public void DeleteUndelete(StatUnitTypes unitType, int id, bool toDelete)
        {
            IStatisticalUnit unit;
            try
            {
                unit = GetStatisticalUnitById(unitType, id);
            }
            catch (NotFoundException ex)
            {
                throw new NotFoundException(ex.Message);
            }

            _deleteUndeleteActions[unit.GetType()](unit, toDelete);
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteEnterpriseUnits(IStatisticalUnit statUnit,
            bool toDelete)
        {
            ((EnterpriseUnit)statUnit).IsDeleted = toDelete;
        }

        private void DeleteUndeleteEnterpriseGroupUnit(IStatisticalUnit statUnit,
            bool toDelete)
        {
            ((EnterpriseGroup)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLegalUnits(IStatisticalUnit statUnit, bool toDelete)
        {
            ((LegalUnit)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLocalUnits(IStatisticalUnit statUnit, bool toDelete)
        {
            ((LocalUnit)statUnit).IsDeleted = toDelete;
        }

        #endregion

        #region CREATE

        public void CreateLegalUnit(LegalUnitCreateM data)
        {
            var unit = Mapper.Map<LegalUnitCreateM, LegalUnit>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<LegalUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            _dbContext.LegalUnits.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.CreateLegalUnitError), e);
            }
        }

        public void CreateLocalUnit(LocalUnitCreateM data)
        {
            var unit = Mapper.Map<LocalUnitCreateM, LocalUnit>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<LocalUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            _dbContext.LocalUnits.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.CreateLocalUnitError), e);
            }
        }

        public void CreateEnterpriseUnit(EnterpriseUnitCreateM data)
        {
            var unit = Mapper.Map<EnterpriseUnitCreateM, EnterpriseUnit>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<EnterpriseUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            _dbContext.EnterpriseUnits.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.CreateEnterpriseUnitError), e);
            }
        }

        public void CreateEnterpriseGroupUnit(EnterpriseGroupCreateM data)
        {
            var unit = Mapper.Map<EnterpriseGroupCreateM, EnterpriseGroup>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<EnterpriseGroup>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            _dbContext.EnterpriseGroups.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.CreateEnterpriseGroupError), e);
            }
        }

        #endregion

        #region EDIT

        public void EditLegalUnit(LegalUnitEditM data)
        {
            var unit = (LegalUnit)ValidateChanges<LegalUnit>(data, data.RegId);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            Mapper.Map(data, unit);
            AddAddresses(unit, data);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.UpdateLegalUnitError), e);
            }
        }

        public void EditLocalUnit(LocalUnitEditM data)
        {
            var unit = (LocalUnit)ValidateChanges<LocalUnit>(data, data.RegId);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            Mapper.Map(data, unit);
            AddAddresses(unit, data);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.UpdateLocalUnitError), e);
            }
        }

        public void EditEnterpiseUnit(EnterpriseUnitEditM data)
        {
            var unit = (EnterpriseUnit)ValidateChanges<EnterpriseUnit>(data, data.RegId);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            Mapper.Map(data, unit);
            AddAddresses(unit, data);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.UpdateEnterpriseUnitError), e);
            }
        }

        public void EditEnterpiseGroup(EnterpriseGroupEditM data)
        {
            var unit = (EnterpriseGroup)ValidateChanges<EnterpriseGroup>(data, data.RegId);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            Mapper.Map(data, unit);
            AddAddresses(unit, data);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.UpdateEnterpriseGroupError), e);
            }
        }

        #endregion

        private void AddAddresses(IStatisticalUnit unit, IStatUnitM data)
        {
            if ((data.Address != null) && (!data.Address.IsEmpty()))
                unit.Address = GetAddress(data.Address);
            else unit.Address = null;
            if ((data.ActualAddress != null) && (!data.ActualAddress.IsEmpty()))
                unit.ActualAddress = data.ActualAddress.Equals(data.Address)
                    ? unit.Address
                    : GetAddress(data.ActualAddress);
            else unit.ActualAddress = null;
        }

        private Address GetAddress(AddressM data)
        {

            return _dbContext.Address.SingleOrDefault(a
                       => a.AddressPart1 == data.AddressPart1 &&
                          a.AddressPart2 == data.AddressPart2 &&
                          a.AddressPart3 == data.AddressPart3 &&
                          a.AddressPart4 == data.AddressPart4 &&
                          a.AddressPart5 == data.AddressPart5 &&
                          a.GpsCoordinates == data.GpsCoordinates)
                   ?? new Address()
                   {
                       AddressPart1 = data.AddressPart1,
                       AddressPart2 = data.AddressPart2,
                       AddressPart3 = data.AddressPart3,
                       AddressPart4 = data.AddressPart4,
                       AddressPart5 = data.AddressPart5,
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
                    .ToList()
                    .Where(u => u.Name == name);
            return
                units.All(
                    unit =>
                            (!address.Equals(unit.Address) && !actualAddress.Equals(unit.ActualAddress)));
        }

        private IStatisticalUnit ValidateChanges<T>(IStatUnitM data, int? regid)
            where T : class, IStatisticalUnit
        {
            var unit = _dbContext.Set<T>().Include(a => a.Address)
                .Include(aa => aa.ActualAddress)
                .Single(x => x.RegId == regid);

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
    }
}
