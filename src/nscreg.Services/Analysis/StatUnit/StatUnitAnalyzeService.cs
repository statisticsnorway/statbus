using System.Collections.Generic;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data.Constants;
using nscreg.Utilities.Extensions;

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
        public Dictionary<int, Dictionary<string, string[]>> AnalyzeStatUnit(IStatisticalUnit unit)
        {
            var addresses = _ctx.Address.Where(adr => adr.Id == unit.AddressId).ToList();
            return _analyzer.CheckAll(unit, IsRelatedLegalUnit(unit), IsRelatedAcitivities(unit), addresses);
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzeService.AnalyzeStatUnits"/>
        /// </summary>
        public Dictionary<int, Dictionary<string, string[]>> AnalyzeStatUnits(
            List<(int regId, StatUnitTypes unitType)> units)
        {
            var statUnits =
                _ctx.StatisticalUnits.Where(su => su.ParrentId == null &&
                                                  units.Any(unit => unit.regId == su.RegId &&
                                                                    unit.unitType == su.UnitType)).ToList();

            var result = new Dictionary<int, Dictionary<string, string[]>>();

            foreach (var unit in statUnits)
            {
                var addresses = _ctx.Address.Where(adr => adr.Id == unit.AddressId).ToList();
                result.AddRange(_analyzer.CheckAll(unit, IsRelatedLegalUnit(unit), IsRelatedAcitivities(unit), addresses));
            }

            return result;
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
