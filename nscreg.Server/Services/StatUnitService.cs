using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Core;
using nscreg.Server.Models.StatUnits;
using System;
using System.Collections.Generic;
using System.Linq;

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
                    return _dbContext.LegalUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.LocalUnit:
                    return _dbContext.LocalUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseUnit:
                    return _dbContext.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseGroup:
                    return _dbContext.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
            }

            throw new BadRequestException("Statistical unit doesn't exist");
        }

        private IStatisticalUnit GetNotDeletedStatisticalUnitById(StatUnitTypes unitType, int id)
        {
            switch (unitType)
            {
                case StatUnitTypes.LegalUnit:
                    return _dbContext.LegalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.LocalUnit:
                    return _dbContext.LocalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseUnit:
                    return _dbContext.EnterpriseUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseGroup:
                    return _dbContext.EnterpriseGroups.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
            }

            throw new NotFoundException("Statistical unit doesn't exist");
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

        public void CreateLegalUnit(LegalUnitSubmitM data)
        {
            var unit = new LegalUnit
            {
                EnterpriseRegId = data.EnterpriseRegId,
                EntRegIdDate = DateTime.Now,
                Founders = data.Founders,
                Owner = data.Owner,
                Market = data.Market,
                LegalForm = data.LegalForm,
                InstSectorCode = data.InstSectorCode,
                TotalCapital = data.TotalCapital,
                MunCapitalShare = data.MunCapitalShare,
                StateCapitalShare = data.StateCapitalShare,
                PrivCapitalShare = data.PrivCapitalShare,
                ForeignCapitalShare = data.ForeignCapitalShare,
                ForeignCapitalCurrency = data.ForeignCapitalCurrency,
                ActualMainActivity1 = data.ActualMainActivity1,
                ActualMainActivity2 = data.ActualMainActivity2,
                ActualMainActivityDate = data.ActualMainActivityDate
            };
            FillBaseFields(unit, data);
            _dbContext.LegalUnits.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Legal Unit", e);
            }
        }

        public void CreateLocalUnit(LocalUnitSubmitM data)
        {

            var unit = new LocalUnit
            {
                LegalUnitId = data.LegalUnitId,
                LegalUnitIdDate = data.LegalUnitIdDate
            };
            FillBaseFields(unit, data);
            _dbContext.LocalUnits.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Local Unit", e);
            }
        }

        public void CreateEnterpriseUnit(EnterpriseUnitSubmitM data)
        {
            var unit = new EnterpriseUnit
            {
                EntGroupId = data.EntGroupId,
                EntGroupIdDate = data.EntGroupIdDate,
                Commercial = data.Commercial,
                InstSectorCode = data.InstSectorCode,
                TotalCapital = data.TotalCapital,
                MunCapitalShare = data.MunCapitalShare,
                StateCapitalShare = data.StateCapitalShare,
                PrivCapitalShare = data.PrivCapitalShare,
                ForeignCapitalShare = data.ForeignCapitalShare,
                ForeignCapitalCurrency = data.ForeignCapitalCurrency,
                ActualMainActivity1 = data.ActualMainActivity1,
                ActualMainActivity2 = data.ActualMainActivity2,
                ActualMainActivityDate = data.ActualMainActivityDate,
                EntGroupRole = data.EntGroupRole

            };
            FillBaseFields(unit, data);
            _dbContext.EnterpriseUnits.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Enterprise Unit", e);
            }
        }

        public void CreateEnterpriseGroupUnit(EnterpriseGroupSubmitM data)
        {
            var unit = new EnterpriseGroup
            {
                RegIdDate = DateTime.Now,
                StatId = data.StatId,
                StatIdDate = data.StatIdDate,
                TaxRegId = data.TaxRegId,
                TaxRegDate = data.TaxRegDate,
                ExternalId = data.ExternalId,
                ExternalIdType = data.ExternalIdType,
                ExternalIdDate = data.ExternalIdDate,
                DataSource = data.DataSource,
                Name = data.Name,
                ShortName = data.ShortName,
                PostalAddressId = data.PostalAddressId,
                TelephoneNo = data.TelephoneNo,
                EmailAddress = data.EmailAddress,
                WebAddress = data.WebAddress,
                EntGroupType = data.EntGroupType,
                RegistrationDate = data.RegistrationDate,
                RegistrationReason = data.RegistrationReason,
                LiqDateStart = data.LiqDateStart,
                LiqDateEnd = data.LiqDateEnd,
                LiqReason = data.LiqReason,
                SuspensionStart = data.SuspensionStart,
                SuspensionEnd = data.SuspensionEnd,
                ReorgTypeCode = data.ReorgTypeCode,
                ReorgDate = data.ReorgDate,
                ReorgReferences = data.ReorgReferences,
                ContactPerson = data.ContactPerson,
                Employees = data.Employees,
                EmployeesFte = data.EmployeesFte,
                EmployeesYear = data.EmployeesYear,
                EmployeesDate = data.EmployeesDate,
                Turnover = data.Turnover,
                TurnoverYear = data.TurnoverYear,
                TurnoveDate = data.TurnoveDate,
                Status = data.Status,
                StatusDate = data.StatusDate,
                Notes = data.Notes
            };
            if (!string.IsNullOrEmpty(data.AddressPart1) ||
                !string.IsNullOrEmpty(data.AddressPart2) ||
                !string.IsNullOrEmpty(data.AddressPart3) ||
                !string.IsNullOrEmpty(data.AddressPart4) ||
                !string.IsNullOrEmpty(data.AddressPart5) ||
                !string.IsNullOrEmpty(data.GeographicalCodes) ||
                !string.IsNullOrEmpty(data.GpsCoordinates))
                unit.Address = GetAddress<EnterpriseGroup>(data);
            if (!string.IsNullOrEmpty(data.ActualAddressPart1) ||
                !string.IsNullOrEmpty(data.ActualAddressPart2) ||
                !string.IsNullOrEmpty(data.ActualAddressPart3) ||
                !string.IsNullOrEmpty(data.ActualAddressPart4) ||
                !string.IsNullOrEmpty(data.ActualAddressPart5) ||
                !string.IsNullOrEmpty(data.ActualGeographicalCodes) ||
                !string.IsNullOrEmpty(data.ActualGpsCoordinates))
                unit.ActualAddress = GetActualAddress<EnterpriseGroup>(data, unit.Address);
            _dbContext.EnterpriseGroups.Add(unit);
            try
            {
                _dbContext.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Enterprise Group", e);
            }
        }

        public Address GetAddress<T>(IStatUnitSubmitM data) where T : class, IStatisticalUnit
        {

            var units = _dbContext.Set<T>().ToList().Where(u => u.Name == data.Name);
            foreach (var unit in units)
            {
                var unitAddress = _dbContext.Address.SingleOrDefault(a => a.Id == unit.AddressId);
                if (unitAddress == null) continue;
                if ((unitAddress.GpsCoordinates != null && data.GpsCoordinates != null) &&
                    unitAddress.GpsCoordinates.Equals(data.GpsCoordinates))
                {
                    throw new BadRequestException(
                        typeof(T).Name + "Error: Name with same GPS Coordinates already excists", null);
                }
                if (((unitAddress.AddressPart1 != null && data.AddressPart1 != null) &&
                     (unitAddress.AddressPart1.Equals(data.AddressPart1))) &&
                    ((unitAddress.AddressPart2 != null && data.AddressPart2 != null) &&
                     (unitAddress.AddressPart2.Equals(data.AddressPart2))) &&
                    ((unitAddress.AddressPart3 != null && data.AddressPart3 != null) &&
                     (unitAddress.AddressPart3.Equals(data.AddressPart3))) &&
                    ((unitAddress.AddressPart4 != null && data.AddressPart4 != null) &&
                     (unitAddress.AddressPart4.Equals(data.AddressPart4))) &&
                    ((unitAddress.AddressPart5 != null && data.AddressPart5 != null) &&
                     (unitAddress.AddressPart5.Equals(data.AddressPart5))))
                {
                    throw new BadRequestException(
                        typeof(T).Name + "Error: Name with same Address already excists", null);
                }
            }
            var address =
                _dbContext.Address.SingleOrDefault(a
                    => a.AddressPart1 == data.AddressPart1 &&
                       a.AddressPart2 == data.AddressPart2 &&
                       a.AddressPart3 == data.AddressPart3 &&
                       a.AddressPart4 == data.AddressPart4 &&
                       a.AddressPart5 == data.AddressPart5 &&
                       (a.GpsCoordinates == data.GpsCoordinates))
                ?? new Address
                {
                    AddressPart1 = data.AddressPart1,
                    AddressPart2 = data.AddressPart2,
                    AddressPart3 = data.AddressPart3,
                    AddressPart4 = data.AddressPart4,
                    AddressPart5 = data.AddressPart5,
                    GeographicalCodes = data.GeographicalCodes,
                    GpsCoordinates = data.GpsCoordinates
                };
            return address;
        }

        public Address GetActualAddress<T>(IStatUnitSubmitM data, Address incAddress) where T : class, IStatisticalUnit
        {

            var units = _dbContext.Set<T>().ToList().Where(u => u.Name == data.Name);
            foreach (var unit in units)
            {
                var unitAddress = _dbContext.Address.SingleOrDefault(a => a.Id == unit.ActualAddressId);
                if (unitAddress == null) continue;
                if ((unitAddress.GpsCoordinates != null && data.ActualGpsCoordinates != null) &&
                    unitAddress.GpsCoordinates.Equals(data.ActualGpsCoordinates))
                {
                    throw new BadRequestException(
                        typeof(T).Name + "Error: Name with same (Actual) GPS Coordinates already excists", null);
                }
                if (((unitAddress.AddressPart1 != null && data.ActualAddressPart1 != null) &&
                     (unitAddress.AddressPart1.Equals(data.ActualAddressPart1))) &&
                    ((unitAddress.AddressPart2 != null && data.ActualAddressPart2 != null) &&
                     (unitAddress.AddressPart2.Equals(data.ActualAddressPart2))) &&
                    ((unitAddress.AddressPart3 != null && data.ActualAddressPart3 != null) &&
                     (unitAddress.AddressPart3.Equals(data.ActualAddressPart3))) &&
                    ((unitAddress.AddressPart4 != null && data.ActualAddressPart4 != null) &&
                     (unitAddress.AddressPart4.Equals(data.ActualAddressPart4))) &&
                    ((unitAddress.AddressPart5 != null && data.ActualAddressPart5 != null) &&
                     (unitAddress.AddressPart5.Equals(data.ActualAddressPart5))))
                {
                    throw new BadRequestException(
                        typeof(T).Name + "Error: Name with same (Actual) Address already excists", null);
                }
            }
            if (incAddress?.Id == 0)
            {
                if (incAddress.AddressPart1.Equals(data.ActualAddressPart1) &&
                    incAddress.AddressPart2.Equals(data.ActualAddressPart2) &&
                    incAddress.AddressPart3.Equals(data.ActualAddressPart3) &&
                    incAddress.AddressPart4.Equals(data.ActualAddressPart4) &&
                    incAddress.AddressPart5.Equals(data.ActualAddressPart5) &&
                    incAddress.GeographicalCodes.Equals(data.GeographicalCodes) &&
                    incAddress.GpsCoordinates.Equals(data.GpsCoordinates)) return incAddress;
            }
            var address =
                _dbContext.Address.SingleOrDefault(a =>
                    a.AddressPart1 == data.ActualAddressPart1 &&
                    a.AddressPart2 == data.ActualAddressPart2 &&
                    a.AddressPart3 == data.ActualAddressPart3 &&
                    a.AddressPart4 == data.ActualAddressPart4 &&
                    a.AddressPart5 == data.ActualAddressPart5 &&
                    (a.GpsCoordinates == data.ActualGpsCoordinates))
                ?? new Address
                {
                    AddressPart1 = data.ActualAddressPart1,
                    AddressPart2 = data.ActualAddressPart2,
                    AddressPart3 = data.ActualAddressPart3,
                    AddressPart4 = data.ActualAddressPart4,
                    AddressPart5 = data.ActualAddressPart5,
                    GeographicalCodes = data.ActualGeographicalCodes,
                    GpsCoordinates = data.ActualGpsCoordinates
                };
            return address;
        }

        private void FillBaseFields(StatisticalUnit unit, StatUnitSubmitM data)
        {
            unit.RegIdDate = DateTime.Now;
            unit.StatId = data.StatId;
            unit.StatIdDate = data.StatIdDate;
            unit.TaxRegId = data.TaxRegId;
            unit.TaxRegDate = data.TaxRegDate;
            unit.ExternalId = data.ExternalId;
            unit.ExternalIdType = data.ExternalIdType;
            unit.ExternalIdDate = data.ExternalIdDate;
            unit.DataSource = data.DataSource;
            unit.RefNo = data.RefNo;
            unit.Name = data.Name;
            unit.ShortName = data.ShortName;
            unit.PostalAddressId = data.PostalAddressId;
            unit.TelephoneNo = data.TelephoneNo;
            unit.EmailAddress = data.EmailAddress;
            unit.WebAddress = data.WebAddress;
            unit.RegMainActivity = data.RegMainActivity;
            unit.RegistrationDate = data.RegistrationDate;
            unit.RegistrationReason = data.RegistrationReason;
            unit.LiqDate = data.LiqDate;
            unit.LiqReason = data.LiqReason;
            unit.SuspensionStart = data.SuspensionStart;
            unit.SuspensionEnd = data.SuspensionEnd;
            unit.ReorgTypeCode = data.ReorgTypeCode;
            unit.ReorgDate = data.ReorgDate;
            unit.ReorgReferences = data.ReorgReferences;
            unit.ContactPerson = data.ContactPerson;
            unit.Employees = data.Employees;
            unit.NumOfPeople = data.NumOfPeople;
            unit.EmployeesYear = data.EmployeesYear;
            unit.EmployeesDate = data.EmployeesDate;
            unit.Turnover = data.Turnover;
            unit.TurnoverYear = data.TurnoverYear;
            unit.TurnoveDate = data.TurnoveDate;
            unit.Status = data.Status;
            unit.StatusDate = data.StatusDate;
            unit.Notes = data.Notes;
            unit.FreeEconZone = data.FreeEconZone;
            unit.ForeignParticipation = data.ForeignParticipation;
            unit.Classified = data.Classified;
            if (!string.IsNullOrEmpty(data.AddressPart1) ||
                !string.IsNullOrEmpty(data.AddressPart2) ||
                !string.IsNullOrEmpty(data.AddressPart3) ||
                !string.IsNullOrEmpty(data.AddressPart4) ||
                !string.IsNullOrEmpty(data.AddressPart5) ||
                !string.IsNullOrEmpty(data.GeographicalCodes) ||
                !string.IsNullOrEmpty(data.GpsCoordinates))
                unit.Address = GetAddress<StatisticalUnit>(data);
            if (!string.IsNullOrEmpty(data.ActualAddressPart1) ||
                !string.IsNullOrEmpty(data.ActualAddressPart2) ||
                !string.IsNullOrEmpty(data.ActualAddressPart3) ||
                !string.IsNullOrEmpty(data.ActualAddressPart4) ||
                !string.IsNullOrEmpty(data.ActualAddressPart5) ||
                !string.IsNullOrEmpty(data.ActualGeographicalCodes) ||
                !string.IsNullOrEmpty(data.ActualGpsCoordinates))
                unit.ActualAddress = GetActualAddress<StatisticalUnit>(data, unit.Address);
        }

        #endregion

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
            Func<int, Func<object, object>> serialize = type => unit => SearchItemVm.Create(unit, type, propNames);
            return _readCtx.LocalUnits.Where(lo => statUnitIds.Any(id => lo.RegId == id)).Select(serialize((int)StatUnitTypes.LocalUnit))
                .Concat(_readCtx.LegalUnits.Where(le => statUnitIds.Any(id => le.RegId == id)).Select(serialize((int)StatUnitTypes.LegalUnit)))
                    .Concat(_readCtx.EnterpriseUnits.Where(en => statUnitIds.Any(id => en.RegId == id)).Select(serialize((int)StatUnitTypes.EnterpriseUnit)));
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
                    throw new NotImplementedException("enterprise group is not supported yet");
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), "unknown statUnit type");
            }
        }

        #endregion
    }
}
