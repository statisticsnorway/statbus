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
        private Dictionary<StatisticalUnitTypes, Action<NSCRegDbContext, StatisticalUnitSubmitM>> _createActions;
        private Dictionary<Type, Action<NSCRegDbContext, IStatisticalUnit, bool>> _deleteUndeleteActions;

        public StatisticalUnitServices()
        {
            _createActions = new Dictionary<StatisticalUnitTypes, Action<NSCRegDbContext, StatisticalUnitSubmitM>>();
            _createActions.Add(StatisticalUnitTypes.LegalUnits, CreateLegalUnit);
            _createActions.Add(StatisticalUnitTypes.LocalUnits, CreateLocalUnit);
            _createActions.Add(StatisticalUnitTypes.EnterpriseUnits, CreateEnterpriseUnit);
            _createActions.Add(StatisticalUnitTypes.EnterpriseGroups, CreateEnterpriseGroupUnit);

            _deleteUndeleteActions = new Dictionary<Type, Action<NSCRegDbContext, IStatisticalUnit, bool>>();
            _deleteUndeleteActions.Add(typeof(EnterpriseGroup), DeleteUndeleteEnterpriseGroupUnit);
            _deleteUndeleteActions.Add(typeof(EnterpriseUnit), DeleteUndeleteEnterpriseUnits);
            _deleteUndeleteActions.Add(typeof(LocalUnit), DeleteUndeleteLocalUnits);
            _deleteUndeleteActions.Add(typeof(LegalUnit), DeleteUndeleteLegalUnits);
        }

        public IStatisticalUnit GetUnitById(NSCRegDbContext context, int unitType, int id)
        {
            var unit = GetStatisticalUnitById(context, unitType, id);
            if (unit == null)
            {
                throw new StaisticalUnitNotFoundException("Statistical unit doesn't exist");
            }
            return unit;
        }

        public void DeleteUndelete(NSCRegDbContext context, int unitType, int id, bool toDelete)
        {
            var unit = GetStatisticalUnitById(context, unitType, id);
            if (unit == null)
            {
                throw new StaisticalUnitNotFoundException("Statistical unit doesn't exist");
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
            }
            return context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);
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

        public void Create(NSCRegDbContext context, StatisticalUnitSubmitM data)
        {
            try
            {
                _createActions[data.UnitType](context, data);
            }
            catch (Exception e)
            {
                throw new StatisticalUnitCreateException("Error while create Statistical Unit", e);
            }
        }

        private void CreateLegalUnit(NSCRegDbContext context, StatisticalUnitSubmitM data)
        {
            var unit = new LegalUnit()
            {
                Name = data.Name
            };
            context.LegalUnits.Add(unit);
        }
        private void CreateLocalUnit(NSCRegDbContext context, StatisticalUnitSubmitM data)
        {
            var unit = new LocalUnit()
            {
                Name = data.Name
            };
            context.LocalUnits.Add(unit);
        }
        private void CreateEnterpriseUnit(NSCRegDbContext context, StatisticalUnitSubmitM data)
        {
            var unit = new EnterpriseUnit()
            {
                Name = data.Name
            };
            context.EnterpriseUnits.Add(unit);
        }
        private void CreateEnterpriseGroupUnit(NSCRegDbContext context, StatisticalUnitSubmitM data)
        {
            var unit = new EnterpriseGroup()
            {
                Name = data.Name
            };
            context.EnterpriseGroups.Add(unit);
        }
    }
}
