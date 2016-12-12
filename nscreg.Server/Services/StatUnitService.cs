using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Core;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Server.Models.StatisticalUnit.Edit;
using nscreg.Server.Models.StatisticalUnit.Submit;
using System;
using System.Collections.Generic;
using System.Linq;

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

        private void AddAddresses(IStatisticalUnit unit, IStatisticalUnitsM data)
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

        public void CreateLegalUnit(LegalUnitSubmitM data)
        {
            var unit = Mapper.Map<LegalUnitSubmitM, LegalUnit>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<LegalUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"Error: Address already excist in DataBase for {data.Name}", null);
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
            var unit = Mapper.Map<LocalUnitSubmitM, LocalUnit>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<LocalUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"Error: Address already excist in DataBase for {data.Name}", null);
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
            var unit = Mapper.Map<EnterpriseUnitSubmitM, EnterpriseUnit>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<EnterpriseUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"Error: Address already excist in DataBase for {data.Name}", null);
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
            var unit = Mapper.Map<EnterpriseGroupSubmitM, EnterpriseGroup>(data);
            AddAddresses(unit, data);
            if (!NameAddressIsUnique<EnterpriseGroup>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"Error: Address already excist in DataBase for {data.Name}", null);
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

        public void EditLegalUnit(LegalUnitEditM data)
        {
            var unit = (LegalUnit) ValidateChanges<LegalUnit>(data, data.RegId);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            Mapper.Map(data, unit);
            AddAddresses(unit, data);
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
            var unit = (LocalUnit)ValidateChanges<LocalUnit>(data, data.RegId);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            Mapper.Map(data, unit);
            AddAddresses(unit, data);
            try
            {
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while update LocalUnit info in DataBase", e);
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
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while update EnterpriseUnit info in DataBase", e);
            }
        }

        public void EditEnterpiseGroup(EnterpriseGroupEditM data)
        {
            var unit = (EnterpriseGroup)ValidateChanges<EnterpriseGroup>(data, data.RegId);
            if (unit == null) throw new ArgumentNullException(nameof(unit));
            Mapper.Map(data,unit);
            AddAddresses(unit, data);
            try
            {
                _context.SaveChanges();
            }
            catch (Exception e)
            {
                throw new BadRequestException("Error while update Enterprise Group info in DataBase", e);
            }
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
            if (address == null) address = new AddressM();
            if (actualAddress == null) actualAddress = new AddressM();
            var units =
                _context.Set<T>()
                    .Include(a => a.Address)
                    .Include(aa => aa.ActualAddress)
                    .ToList()
                    .Where(u => u.Name == name);
            return
                units.All(
                    unit =>
                            (!address.Equals(unit.Address) && !actualAddress.Equals(unit.ActualAddress)));
        }

        private IStatisticalUnit ValidateChanges<T>(IStatisticalUnitsM data, int? regid)
            where T : class, IStatisticalUnit
        {
            const string error = "Error: Address already excist in DataBase for";
            var unit = _context.Set<T>().Include(a => a.Address)
                .Include(aa => aa.ActualAddress)
                .Single(x => x.RegId == regid);

            if (!unit.Name.Equals(data.Name) &&
                !NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {error} {data.Name}", null);
            else if (data.Address != null && data.ActualAddress != null && !data.Address.Equals(unit.Address) &&
                     !data.ActualAddress.Equals(unit.ActualAddress) &&
                     !NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {error} {data.Name}", null);
            else if (data.Address != null && !data.Address.Equals(unit.Address) &&
                     !NameAddressIsUnique<T>(data.Name, data.Address, null))
                throw new BadRequestException(
                    $"{typeof(T).Name} {error} {data.Name}", null);
            else if (data.ActualAddress != null && !data.ActualAddress.Equals(unit.ActualAddress) &&
                     !NameAddressIsUnique<T>(data.Name, null, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {error} {data.Name}", null);

            return unit;
        }
    }
}
