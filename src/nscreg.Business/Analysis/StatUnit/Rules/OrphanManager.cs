using nscreg.Data.Entities;

namespace nscreg.Business.Analysis.StatUnit.Rules
{
    public class OrphanManager
    {
        private readonly EnterpriseUnit _unit;

        public OrphanManager(IStatisticalUnit unit)
        {
            _unit = (EnterpriseUnit)unit;
        }

        public void CheckAssociatedEnterpriseGroup(ref string key, ref string[] value)
        {
            if (_unit.EntGroupId != null) return;
            key = "EnterpriseGroup";
            value = new[] { "Enterprise has no associated with it enterprise group" };
        }
        
    }
}
