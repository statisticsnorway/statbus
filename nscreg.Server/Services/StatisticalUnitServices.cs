using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Data.Enums;
using nscreg.Utilities;

namespace nscreg.Server.Services
{
    public class StatisticalUnitServices
    {
        private static NSCRegDbContext _context;

        private Dictionary<Type, Action<IStatisticalUnit, bool>> _deleteUndeleteActions;

        public StatisticalUnitServices(NSCRegDbContext context)
        {
            _context = context;

            _deleteUndeleteActions = new Dictionary<Type, Action<IStatisticalUnit, bool>>();
            _deleteUndeleteActions.Add(typeof(EnterpriseGroup), DeleteUndeleteEnterpriseGroupUnit);
            _deleteUndeleteActions.Add(typeof(EnterpriseUnit), DeleteUndeleteEnterpriseUnits);
            _deleteUndeleteActions.Add(typeof(LocalUnit), DeleteUndeleteLocalUnits);
            _deleteUndeleteActions.Add(typeof(LegalUnit), DeleteUndeleteLegalUnits);
        }

        public IStatisticalUnit GetUnitById(StatisticalUnitTypes unitType, int id)
        {
            return GetNotDeletedStatisticalUnitById(unitType, id);
        }

        public void DeleteUndelete(StatisticalUnitTypes unitType, int id, bool toDelete)
        {
            IStatisticalUnit unit = GetStatisticalUnitById(unitType, id);

            _deleteUndeleteActions[unit.GetType()](unit, toDelete);
            _context.SaveChanges();
        }

        private static IStatisticalUnit GetStatisticalUnitById(StatisticalUnitTypes unitType, int id)
        {
            switch (unitType)
            {
                case StatisticalUnitTypes.LegalUnits:
                    return _context.LegalUnits.FirstOrDefault(x => x.RegId == id);
                case StatisticalUnitTypes.LocalUnits:
                    return _context.LocalUnits.FirstOrDefault(x => x.RegId == id);
                case StatisticalUnitTypes.EnterpriseUnits:
                    return _context.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
                case StatisticalUnitTypes.EnterpriseGroups:
                    return _context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
            }

            throw new BadRequestException("Statistical unit doesn't exist");
        }

        private static IStatisticalUnit GetNotDeletedStatisticalUnitById(StatisticalUnitTypes unitType, int id)
        {
            switch (unitType)
            {
                case StatisticalUnitTypes.LegalUnits:
                    return _context.LegalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatisticalUnitTypes.LocalUnits:
                    return _context.LocalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatisticalUnitTypes.EnterpriseUnits:
                    return _context.EnterpriseUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case StatisticalUnitTypes.EnterpriseGroups:
                    return _context.EnterpriseGroups.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
            }

            throw new NotFoundException("Statistical unit doesn't exist");
        }

        private static void DeleteUndeleteEnterpriseUnits(IStatisticalUnit statUnit, bool toDelete)
        {
            ((EnterpriseUnit)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLegalUnits(IStatisticalUnit statUnit, bool toDelete)
        {
            ((LegalUnit)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLocalUnits(IStatisticalUnit statUnit, bool toDelete)
        {
            ((LocalUnit)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteEnterpriseGroupUnit(IStatisticalUnit statUnit, bool toDelete)
        {
            ((EnterpriseGroup)statUnit).IsDeleted = toDelete;
        }
    }
}
