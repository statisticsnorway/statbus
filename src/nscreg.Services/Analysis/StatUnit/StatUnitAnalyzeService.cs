using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data.Constants;

namespace nscreg.Services.Analysis.StatUnit
{
    /// <summary>
    /// Stat unit analyzing service
    /// </summary>
    public class StatUnitAnalyzeService : IStatUnitAnalyzeService
    {
        private readonly NSCRegDbContext _ctx;
        private readonly IStatUnitAnalyzer _analyzer;

        public StatUnitAnalyzeService(NSCRegDbContext ctx, IStatUnitAnalyzer analyzer)
        {
            _ctx = ctx;
            _analyzer = analyzer;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzeService.AnalyzeStatUnit"/>
        /// </summary>
        public AnalysisResult AnalyzeStatUnit(IStatisticalUnit unit)
        {
            var addresses = _ctx.Address.Where(adr => adr.Id == unit.AddressId).ToList();
            var potentialDuplicateUnits = GetPotentialDuplicateUnits(unit);

            return _analyzer.CheckAll(unit, IsRelatedLegalUnit(unit), IsRelatedAcitivities(unit), addresses, potentialDuplicateUnits);
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzeService.AnalyzeStatUnits"/>
        /// </summary>
        public void AnalyzeStatUnits()
        {
            var analysisLog = _ctx.AnalysisLogs.LastOrDefault(al => al.ServerEndPeriod == null);
            if (analysisLog == null) return;

            analysisLog.ServerStartPeriod = DateTime.Now;

            var statUnits = _ctx.StatisticalUnits.Where(su => su.ParentId == null &&
                                                  (analysisLog.LastAnalyzedUnitId == null ||
                                                   su.RegId >= analysisLog.LastAnalyzedUnitId))
                    .Include(x => x.PersonsUnits).ToList();
            
            foreach (var unit in statUnits)
            {
                var result = AnalyzeStatUnit(unit);

                foreach (var message in result.Messages)
                {
                    _ctx.AnalysisErrors.Add(new AnalysisError
                    {
                        AnalysisLogId = analysisLog.Id,
                        RegId = unit.RegId,
                        ErrorKey = message.Key,
                        ErrorValue = string.Join(";", message.Value)
                });
                }
                analysisLog.ServerEndPeriod = DateTime.Now;
                analysisLog.LastAnalyzedUnitId = unit.RegId;
                analysisLog.SummaryMessages = string.Join(";", result.SummaryMessages);
                _ctx.SaveChanges();
            }
        }
        

        private List<StatisticalUnit> GetPotentialDuplicateUnits(IStatisticalUnit unit)
        {
            var statUnit = (StatisticalUnit)unit;

            var statUnitPerson = statUnit.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner);

            var units = _ctx.StatisticalUnits
                .Include(x => x.PersonsUnits)
                .Where(su =>
                    su.UnitType == unit.UnitType &&
                    ((su.StatId == unit.StatId && su.TaxRegId == unit.TaxRegId) || su.ExternalId == unit.ExternalId ||
                     su.Name == unit.Name ||
                     su.ShortName == statUnit.ShortName ||
                     su.TelephoneNo == statUnit.TelephoneNo ||
                     su.AddressId == unit.AddressId ||
                     su.EmailAddress == statUnit.EmailAddress ||
                     su.ContactPerson == statUnit.ContactPerson ||
                     su.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) != null && statUnitPerson != null &&
                     (su.PersonsUnits.FirstOrDefault(pu => pu.PersonType == PersonTypes.Owner) == statUnitPerson)
                    )).ToList();

            return units;
        }

        private bool IsRelatedLegalUnit(IStatisticalUnit unit)
        {
            switch (unit.UnitType)
            {
                case StatUnitTypes.LocalUnit:
                    return _ctx.LegalUnits.Any(le => le.RegId == ((LocalUnit) unit).LegalUnitId);
                case StatUnitTypes.EnterpriseUnit:
                    return
                        _ctx.LegalUnits.Any(le => le.EnterpriseUnitRegId == ((EnterpriseUnit) unit).RegId);
                case StatUnitTypes.LegalUnit:
                    return false;
                case StatUnitTypes.EnterpriseGroup:
                    return false;
                default:
                    return false;
            }
        }

        private bool IsRelatedAcitivities(IStatisticalUnit unit)
        {
            return _ctx.ActivityStatisticalUnits.Where(asu => asu.UnitId == unit.RegId)
                .Include(x => x.Activity).Select(x => x.Activity).Any();
        }
        
    }
}
