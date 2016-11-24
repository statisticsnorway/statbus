using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Models.StatisticalUnit;
using System.Collections.Generic;
using System;
using nscreg.Utilities;

namespace nscreg.Server.Services
{
    public class StatisticalUnitServices
    {
        private Dictionary<UnitType, Action<NSCRegDbContext, StatisticalUnitSubmitM>> _createActions;
        private Dictionary<Type, Action<NSCRegDbContext, IStatisticalUnit>> _deleteActions;

        public StatisticalUnitServices()
        {
            _createActions = new Dictionary<UnitType, Action<NSCRegDbContext, StatisticalUnitSubmitM>>();
            _createActions.Add(UnitType.Legal, CreateLegalUnit);
            _createActions.Add(UnitType.Local, CreateLocalUnit);
            _createActions.Add(UnitType.Enterprise, CreateEnterpriseUnit);
            _createActions.Add(UnitType.EnterpriseGroup, CreateEnterpriseGroupUnit);

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
