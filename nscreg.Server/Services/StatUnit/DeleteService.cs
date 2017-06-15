using System;
using System.Collections.Generic;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;
using static nscreg.Server.Services.StatUnit.Common;

namespace nscreg.Server.Services.StatUnit
{
    public class DeleteService
    {
        private readonly Dictionary<StatUnitTypes, Action<int, bool, string>> _deleteUndeleteActions;
        private readonly NSCRegDbContext _dbContext;

        public DeleteService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _deleteUndeleteActions = new Dictionary<StatUnitTypes, Action<int, bool, string>>
            {
                [StatUnitTypes.EnterpriseGroup] = DeleteUndeleteEnterpriseGroupUnit,
                [StatUnitTypes.EnterpriseUnit] = DeleteUndeleteEnterpriseUnit,
                [StatUnitTypes.LocalUnit] = DeleteUndeleteLocalUnit,
                [StatUnitTypes.LegalUnit] = DeleteUndeleteLegalUnit
            };
        }

        public void DeleteUndelete(StatUnitTypes unitType, int id, bool toDelete, string userId)
        {
            _deleteUndeleteActions[unitType](id, toDelete, userId);
        }

        private void DeleteUndeleteEnterpriseGroupUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.EnterpriseGroups.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseGroup();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseGroups.Add((EnterpriseGroup) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteLegalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LegalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LegalUnits.Add((LegalUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteLocalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LocalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LocalUnits.Add((LocalUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteEnterpriseUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseUnits.Add((EnterpriseUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }
    }
}
