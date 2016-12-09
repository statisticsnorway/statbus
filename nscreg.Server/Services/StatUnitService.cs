using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Core;
using nscreg.Server.Models.StatisticalUnit;
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using nscreg.Server.Models.StatisticalUnit.Edit;
using nscreg.Server.Models.StatisticalUnit.Submit;

namespace nscreg.Server.Services
{
    public class StatUnitService
    {
        private readonly Dictionary<Type, Action<IStatisticalUnit, bool>> _deleteUndeleteActions;
        private readonly NSCRegDbContext _context;

        public StatUnitService(NSCRegDbContext context)
        {
            _context = context;
            _deleteUndeleteActions = new Dictionary<Type, Action<IStatisticalUnit, bool>>
            {
                {typeof(EnterpriseGroup), DeleteUndeleteEnterpriseGroupUnit},
                {typeof(EnterpriseUnit), DeleteUndeleteEnterpriseUnits},
                {typeof(LocalUnit), DeleteUndeleteLocalUnits},
                {typeof(LegalUnit), DeleteUndeleteLegalUnits}
            };
        }

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
            _context.SaveChanges();
        }

        private IStatisticalUnit GetStatisticalUnitById(StatUnitTypes unitType, int id)
        {
            switch (unitType)
            {
                case StatUnitTypes.LegalUnit:
                    return _context.LegalUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.LocalUnit:
                    return _context.LocalUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseUnit:
                    return _context.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseGroup:
                    return _context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
            }

            throw new BadRequestException("Statistical unit doesn't exist");
        }

        private IStatisticalUnit GetNotDeletedStatisticalUnitById(StatUnitTypes unitType, int id)
        {
            switch (unitType)
            {
                case StatUnitTypes.LegalUnit:
                    return _context.LegalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.LocalUnit:
                    return _context.LocalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseUnit:
                    return _context.EnterpriseUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatUnitTypes.EnterpriseGroup:
                    return _context.EnterpriseGroups.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
            }

            throw new NotFoundException("Statistical unit doesn't exist");
        }

        private void DeleteUndeleteEnterpriseUnits(IStatisticalUnit statUnit,
            bool toDelete)
        {
            ((EnterpriseUnit) statUnit).IsDeleted = toDelete;
        }

        private void DeleteUndeleteEnterpriseGroupUnit(IStatisticalUnit statUnit,
            bool toDelete)
        {
            ((EnterpriseGroup) statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLegalUnits(IStatisticalUnit statUnit, bool toDelete)
        {
            ((LegalUnit) statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLocalUnits(IStatisticalUnit statUnit, bool toDelete)
        {
            ((LocalUnit) statUnit).IsDeleted = toDelete;
        }

        private void FillBaseFields(StatisticalUnit unit, StatisticalUnitSubmitM data)
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
            if ((data.Address != null) && (!data.Address.IsEmpty()))
                unit.Address = GetAddress(data.Address);
            if ((data.ActualAddress != null) && (!data.ActualAddress.IsEmpty()))
                unit.ActualAddress = data.ActualAddress.Equals(data.Address)
                    ? unit.Address
                    : GetAddress(data.ActualAddress);
            if (!NameAddressIsUnique<StatisticalUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException("Error: Address already excist in DataBase for \"" + data.Name + "\"", null);
        }

        public void CreateLegalUnit(LegalUnitSubmitM data)
        {
            var unit = new LegalUnit()
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
            _context.LegalUnits.Add(unit);
            try
            {
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Legal Unit", e);
            }
        }

        public void CreateLocalUnit(LocalUnitSubmitM data)
        {

            var unit = new LocalUnit()
            {
                LegalUnitId = data.LegalUnitId,
                LegalUnitIdDate = data.LegalUnitIdDate
            };
            FillBaseFields(unit, data);
            _context.LocalUnits.Add(unit);
            try
            {
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Local Unit", e);
            }
        }

        public void CreateEnterpriseUnit(EnterpriseUnitSubmitM data)
        {
            var unit = new EnterpriseUnit()
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
            _context.EnterpriseUnits.Add(unit);
            try
            {
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Enterprise Unit", e);
            }
        }

        public void CreateEnterpriseGroupUnit(EnterpriseGroupSubmitM data)
        {
            var unit = new EnterpriseGroup()
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
            if ((data.Address != null) && (!data.Address.IsEmpty()))
                unit.Address = GetAddress(data.Address);
            if ((data.ActualAddress != null) && (!data.ActualAddress.IsEmpty()))
                unit.ActualAddress = data.ActualAddress.Equals(data.Address)
                    ? unit.Address
                    : GetAddress(data.ActualAddress);
            if (!NameAddressIsUnique<EnterpriseGroup>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException("Error: Address already excist in DataBase for \"" + data.Name + "\"", null);
            _context.EnterpriseGroups.Add(unit);
            try
            {
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while create Enterprise Group", e);
            }
        }

        private void EditBaseFields(StatisticalUnit unit, StatisticalUnitEditM data)
        {
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
        }

        public void EditLegalUnit(LegalUnitEditM data)
        {
            LegalUnit unit;
            try
            {
                unit = _context.LegalUnits.Include(a => a.Address)
                    .Include(aa => aa.ActualAddress)
                    .Single(x => x.RegId == data.RegId);
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while fetching LegalUnit info from DataBase", e);
            }
            unit.EnterpriseRegId = data.EnterpriseRegId;
            unit.Founders = data.Founders;
            unit.Owner = data.Owner;
            unit.Market = data.Market;
            unit.LegalForm = data.LegalForm;
            unit.InstSectorCode = data.InstSectorCode;
            unit.TotalCapital = data.TotalCapital;
            unit.MunCapitalShare = data.MunCapitalShare;
            unit.StateCapitalShare = data.StateCapitalShare;
            unit.PrivCapitalShare = data.PrivCapitalShare;
            unit.ForeignCapitalShare = data.ForeignCapitalShare;
            unit.ForeignCapitalCurrency = data.ForeignCapitalCurrency;
            unit.ActualMainActivity1 = data.ActualMainActivity1;
            unit.ActualMainActivity2 = data.ActualMainActivity2;
            unit.ActualMainActivityDate = data.ActualMainActivityDate;
            EditBaseFields(unit, data);
            try
            {
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while update LegalUnit info in DataBase", e);
            }
        }

        public void EditLocalUnit(LocalUnitEditM data)
        {

        }

        public void EditEnterpiseUnit(EnterpriseUnitEditM data)
        {

        }

        public void EditEnterpiseGroup(EnterpriseGroupEditM data)
        {

        }

        private Address GetAddress(AddressM data)
        {

            return _context.Address.SingleOrDefault(a
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
            var units =
                _context.Set<T>()
                    .Include(a => a.Address)
                    .Include(aa => aa.ActualAddress)
                    .ToList()
                    .Where(u => u.Name == name);
            return
                units.All(
                    unit =>
                        (!address.Equals(unit.Address) && !address.Equals(unit.ActualAddress)) ||
                        (!actualAddress.Equals(unit.Address) && !actualAddress.Equals(unit.ActualAddress)));
        }
    }
}
