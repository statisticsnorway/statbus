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
        private Dictionary<Type, Action<NSCRegDbContext, IStatisticalUnit, bool>> _deleteUndeleteActions;

        public StatisticalUnitServices()
        {
            _deleteUndeleteActions = new Dictionary<Type, Action<NSCRegDbContext, IStatisticalUnit, bool>>();
            _deleteUndeleteActions.Add(typeof(EnterpriseGroup), DeleteUndeleteEnterpriseGroupUnit);
            _deleteUndeleteActions.Add(typeof(EnterpriseUnit), DeleteUndeleteEnterpriseUnits);
            _deleteUndeleteActions.Add(typeof(LocalUnit), DeleteUndeleteLocalUnits);
            _deleteUndeleteActions.Add(typeof(LegalUnit), DeleteUndeleteLegalUnits);
        }

        public IStatisticalUnit GetUnitById(NSCRegDbContext context, int unitType, int id)
        {
            IStatisticalUnit unit;
            try
            {
                unit = GetNotDeletedStatisticalUnitById(context, unitType, id);
            }
            catch (MyNotFoundException ex)
            {
                throw new MyNotFoundException(ex.Message);
            }
            return unit;
        }

        public void DeleteUndelete(NSCRegDbContext context, int unitType, int id, bool toDelete)
        {
            IStatisticalUnit unit;
            try
            {
                unit = GetStatisticalUnitById(context, unitType, id);
            }
            catch (MyNotFoundException ex)
            {
                throw new MyNotFoundException(ex.Message);
            }

            _deleteUndeleteActions[unit.GetType()](context, unit, toDelete);
            context.SaveChanges();
        }

        private static IStatisticalUnit GetStatisticalUnitById(NSCRegDbContext context, int unitType, int id)
        {
            switch (unitType)
            {
                case (int)StatUnitTypes.LegalUnit:
                    return context.LegalUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatUnitTypes.LocalUnit:
                    return context.LocalUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatUnitTypes.EnterpriseUnit:
                    return context.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatUnitTypes.EnterpriseGroup:
                    return context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
            }

            throw new MyNotFoundException("Statistical unit doesn't exist");
        }

        private static IStatisticalUnit GetNotDeletedStatisticalUnitById(NSCRegDbContext context, int unitType, int id)
        {
            switch (unitType)
            {
                case (int)StatUnitTypes.LegalUnit:
                    return context.LegalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case (int)StatUnitTypes.LocalUnit:
                    return context.LocalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case (int)StatUnitTypes.EnterpriseUnit:
                    return context.EnterpriseUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case (int)StatUnitTypes.EnterpriseGroup:
                    return context.EnterpriseGroups.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
            }

            throw new MyNotFoundException("Statistical unit doesn't exist");
        }

        private static void DeleteUndeleteEnterpriseUnits(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((EnterpriseUnit)statUnit).IsDeleted = toDelete;
        }
        private static void DeleteUndeleteEnterpriseGroupUnit(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((EnterpriseGroup)statUnit).IsDeleted = toDelete;
        }
        private static void DeleteUndeleteLegalUnits(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((LegalUnit)statUnit).IsDeleted = toDelete;
        }
        private static void DeleteUndeleteLocalUnits(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((LocalUnit)statUnit).IsDeleted = toDelete;
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
            if (!string.IsNullOrEmpty(data.AddressPart1) ||
                !string.IsNullOrEmpty(data.AddressPart2) ||
                !string.IsNullOrEmpty(data.AddressPart3) ||
                !string.IsNullOrEmpty(data.AddressPart4) ||
                !string.IsNullOrEmpty(data.AddressPart5) ||
                !string.IsNullOrEmpty(data.GeographicalCodes) ||
                !string.IsNullOrEmpty(data.GpsCoordinates))
                unit.Address = new Address()
                {
                    AddressPart1 = data.AddressPart1,
                    AddressPart2 = data.AddressPart2,
                    AddressPart3 = data.AddressPart3,
                    AddressPart4 = data.AddressPart4,
                    AddressPart5 = data.AddressPart5,
                    GeographicalCodes = data.GeographicalCodes,
                    GpsCoordinates = data.GpsCoordinates
                };
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
            try
            {
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Legal Unit", e);
            }
        }
        public void CreateLocalUnit(NSCRegDbContext context, LocalUnitSubmitM data)
        {

            var unit = new LocalUnit()
            {
                LegalUnitId = data.LegalUnitId,
                LegalUnitIdDate = data.LegalUnitIdDate
            };
            FillBaseFields(unit, data);
            context.LocalUnits.Add(unit);
            try
            {
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Local Unit", e);
            }
        }
        public void CreateEnterpriseUnit(NSCRegDbContext context, EnterpriseUnitSubmitM data)
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
            try
            {
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Enterprise Unit", e);
            }
        }
        public void CreateEnterpriseGroupUnit(NSCRegDbContext context, EnterpriseGroupSubmitM data)
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
            if (!string.IsNullOrEmpty(data.AddressPart1) ||
            !string.IsNullOrEmpty(data.AddressPart2) ||
            !string.IsNullOrEmpty(data.AddressPart3) ||
            !string.IsNullOrEmpty(data.AddressPart4) ||
            !string.IsNullOrEmpty(data.AddressPart5) ||
            !string.IsNullOrEmpty(data.GeographicalCodes) ||
            !string.IsNullOrEmpty(data.GpsCoordinates))
                unit.Address = new Address()
                {
                    AddressPart1 = data.AddressPart1,
                    AddressPart2 = data.AddressPart2,
                    AddressPart3 = data.AddressPart3,
                    AddressPart4 = data.AddressPart4,
                    AddressPart5 = data.AddressPart5,
                    GeographicalCodes = data.GeographicalCodes,
                    GpsCoordinates = data.GpsCoordinates
                };

            context.EnterpriseGroups.Add(unit);
            try
            {
                context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Enterprise Group", e);
            }
        }
    }
}
