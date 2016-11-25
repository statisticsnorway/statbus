using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Data.Enums;
using nscreg.Utilities;

namespace nscreg.Server.Services
{
    public class StatisticalUnitServices
    {
        private Dictionary<Type, Action<NSCRegDbContext, IStatisticalUnit>> _deleteActions;

        public StatisticalUnitServices()
        {
            _deleteActions = new Dictionary<Type, Action<NSCRegDbContext, IStatisticalUnit>>();
            _deleteActions.Add(typeof(EnterpriseGroup), DeleteEnterpriseGroupUnit);
            _deleteActions.Add(typeof(EnterpriseUnit), DeleteEnterpriseUnits);
            _deleteActions.Add(typeof(LocalUnit), DeleteLocalUnits);
            _deleteActions.Add(typeof(LegalUnit), DeleteLegalUnits);
        }

        public void Delete(NSCRegDbContext context, int unitType, int id)
        {
            var unit = GetStatisticalUnitById(context, unitType, id);
            if (unit == null)
            {
                throw new UnitNotFoundException("Statistical unit doesn't exist");
            }

            _deleteActions[unit.GetType()](context, unit);
        }

        private static IStatisticalUnit GetStatisticalUnitById(NSCRegDbContext context, int unitType, int id)
        {
            switch (unitType)
            {
                case (int)StatisticalUnitTypes.LegalUnits:
                    return context.LegalUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.LocalUnits:
                    return context.LocalUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.EnterpriseUnits:
                    return context.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
            }
            return context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
        }

        private static void DeleteEnterpriseUnits(NSCRegDbContext context, IStatisticalUnit statUnit)
        {
            ((EnterpriseUnit)statUnit).IsDeleted = true;
            context.SaveChanges();
        }

        private static void DeleteLegalUnits(NSCRegDbContext context, IStatisticalUnit statUnit)
        {
            ((LegalUnit)statUnit).IsDeleted = true;
            context.SaveChanges();
        }

        private static void DeleteLocalUnits(NSCRegDbContext context, IStatisticalUnit statUnit)
        {
            ((LocalUnit)statUnit).IsDeleted = true;
            context.SaveChanges();
        }

        private static void DeleteEnterpriseGroupUnit(NSCRegDbContext context, IStatisticalUnit statUnit)
        {
            ((EnterpriseGroup)statUnit).IsDeleted = true;
            context.SaveChanges();
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
            unit.AddressId = data.AddressId;
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
            unit.ActualAddressId = data.ActualAddressId;
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
        public void CreateLegalUnit(NSCRegDbContext context, LegalUnitSubmitM data)
        {
            try
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
                context.LegalUnits.Add(unit);
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Legal Unit", e);
            }
        }
        public void CreateLocalUnit(NSCRegDbContext context, LocalUnitSubmitM data)
        {
            try
            {
                var unit = new LocalUnit()
                {
                    LegalUnitId = data.LegalUnitId,
                    LegalUnitIdDate = data.LegalUnitIdDate
                };
                FillBaseFields(unit, data);
                context.LocalUnits.Add(unit);
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Local Unit", e);
            }
        }
        public void CreateEnterpriseUnit(NSCRegDbContext context, EnterpriseUnitSubmitM data)
        {
            try
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
                context.EnterpriseUnits.Add(unit);
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Enterprise Unit", e);
            }
        }

        public void CreateEnterpriseGroupUnit(NSCRegDbContext context, EnterpriseGroupSubmitM data)
        {
            try
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
                    AddressId = data.AddressId,
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
                    ActualAddressId = data.ActualAddressId,
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
                context.EnterpriseGroups.Add(unit);
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Enterprise Group", e);
            }
        }
    }
}


