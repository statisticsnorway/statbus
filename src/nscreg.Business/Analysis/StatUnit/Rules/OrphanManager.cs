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

        public (string, string[]) CheckAssociatedEnterpriseGroup()
        {
            return (_unit.EntGroupId != null)
                ? (null, null)
                : ("EnterpriseGroup", new[] {"Enterprise has no associated with it enterprise group"});
        }
        
    }
}
