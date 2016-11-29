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
            catch(MyNotFoundException ex)
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
                case (int)StatisticalUnitTypes.LegalUnits:
                    return context.LegalUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.LocalUnits:
                    return context.LocalUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.EnterpriseUnits:
                    return context.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.EnterpriseGroups:
                    return context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
            }

            throw new MyNotFoundException("Statistical unit doesn't exist");
        }

        private static IStatisticalUnit GetNotDeletedStatisticalUnitById(NSCRegDbContext context, int unitType, int id)
        {
            switch (unitType)
            {
                case (int)StatisticalUnitTypes.LegalUnits:
                    return context.LegalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.LocalUnits:
                    return context.LocalUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.EnterpriseUnits:
                    return context.EnterpriseUnits.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
                case (int)StatisticalUnitTypes.EnterpriseGroups:
                    return context.EnterpriseGroups.Where(x => x.IsDeleted == false).FirstOrDefault(x => x.RegId == id);
            }

            throw new MyNotFoundException("Statistical unit doesn't exist");
        }

        private static void DeleteUndeleteEnterpriseUnits(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((EnterpriseUnit)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLegalUnits(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((LegalUnit)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteLocalUnits(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((LocalUnit)statUnit).IsDeleted = toDelete;
        }

        private static void DeleteUndeleteEnterpriseGroupUnit(NSCRegDbContext context, IStatisticalUnit statUnit, bool toDelete)
        {
            ((EnterpriseGroup)statUnit).IsDeleted = toDelete;
        }
    }
}
