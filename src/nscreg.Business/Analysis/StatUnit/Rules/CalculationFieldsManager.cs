using System;
using nscreg.Data.Entities;
using System.Linq;

namespace nscreg.Business.Analysis.StatUnit.Rules
{
    public class CalculationFieldsManager
    {
        private readonly StatisticalUnit _statisticalUnit;
        private readonly EnterpriseGroup _enterpriseGroup;

        public CalculationFieldsManager(IStatisticalUnit unit)
        {
            _enterpriseGroup = unit as EnterpriseGroup;
            _statisticalUnit = unit as StatisticalUnit;
        }

        public (string, string[]) CheckOkpo()
        {
            var okpo = _enterpriseGroup == null ? _statisticalUnit.StatId : _enterpriseGroup.StatId;
            if (okpo == null) return (null, null);

            var sum = okpo.Select((s, i) => Convert.ToInt32(s) * (i + 1)).Sum();
            var remainder = sum % 11;
            if (remainder >= 10)
                sum = okpo.Select((s, i) => Convert.ToInt32(s) * (i + 3)).Sum();

            remainder = sum % 11;
            var checkNumber = remainder >= 10 ? 0 : sum - 11 * (sum / 11);

            return remainder == checkNumber || remainder == 10 && checkNumber == 0
                ? (null, null)
                : (nameof(_statisticalUnit.StatId), new[] { "Stat unit's \"StatId\" is incorrect" });
        }
    }
}
