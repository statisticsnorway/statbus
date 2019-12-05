using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Helpers
{
    /// <summary>
    /// History Holder Class
    /// </summary>
    public class UnitsHistoryHolder
    {
        public UnitsHistoryHolder(IStatisticalUnit unit)
        {
            switch (unit.GetType().Name)
            {
                case nameof(LocalUnit):
                {
                    var localUnit = unit as LocalUnit;

                    HistoryUnits = (localUnit?.LegalUnitId, null, null, null, null, null);
                    break;
                }
                case nameof(LegalUnit):
                {
                    var legalUnit = unit as LegalUnit;

                    HistoryUnits = (
                            null, 
                            legalUnit?.EnterpriseUnitRegId,
                            null,
                            legalUnit?.LocalUnits.Select(x => x.RegId).ToList(),
                            null,
                            null);
                    break;
                }
                case nameof(EnterpriseUnit):
                {
                    var enterpriseUnit = unit as EnterpriseUnit;

                    HistoryUnits = (
                            null,
                            null,
                            enterpriseUnit?.EntGroupId,
                            null,
                            enterpriseUnit?.LegalUnits.Select(x => x.RegId).ToList(),
                            null);
                    break;
                }
                case nameof(EnterpriseGroup):
                {
                    var enterpriseGroup = unit as EnterpriseGroup;

                    HistoryUnits = (
                            null,
                            null,
                            null,
                            null,
                            null,
                            enterpriseGroup?.EnterpriseUnits.Select(x => x.RegId).ToList());
                    break;
                }
            }
        }

        public (int? legalUnitId,
            int? enterpriseUnitId,
            int? enterpriseGroupId,
            List<int> localUnitsIds,
            List<int> legalUnitsIds,
            List<int> enterpriseUnitsIds) HistoryUnits
        { get; }
    }
}
