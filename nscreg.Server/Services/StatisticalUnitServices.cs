using System.Linq;
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
        Dictionary<UnitType, Action<NSCRegDbContext, StatisticalUnitSubmitM>> _createActions;

        public StatisticalUnitServices()
        {
            _createActions = new Dictionary<UnitType, Action<NSCRegDbContext, StatisticalUnitSubmitM>>();
            _createActions.Add(UnitType.Legal, CreateLegalUnit);
            _createActions.Add(UnitType.Local, CreateLocalUnit);
            _createActions.Add(UnitType.Enterprise, CreateEnterpriseUnit);
            _createActions.Add(UnitType.EnterpriseGroup, CreateEnterpriseGroupUnit);
        }
        public static string Delete(NSCRegDbContext context, int id)
        {
            var localStatUnit = context.LocalUnits.FirstOrDefault(x => x.RegId == id);
            var legalStatUnit = context.LegalUnits.FirstOrDefault(x => x.RegId == id);
            var entUStatUnit = context.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
            var entGStatUnit = context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);

            if (localStatUnit != null)
            {
                localStatUnit.IsDeleted = true;
                return "OK";
            }
            if (legalStatUnit != null)
            {
                legalStatUnit.IsDeleted = true;
                return "OK";
            }
            if (entUStatUnit != null)
            {
                entUStatUnit.IsDeleted = true;
                return "OK";
            }
            if (entGStatUnit != null)
            {
                entGStatUnit.IsDeleted = true;
                return "OK";
            }

            return "NotFound";
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
