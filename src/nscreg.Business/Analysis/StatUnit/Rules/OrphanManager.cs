using nscreg.Data.Entities;

namespace nscreg.Business.Analysis.StatUnit.Rules
{
    /// <summary>
    /// Stat unit analysis orphan manager
    /// </summary>
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
                : (nameof(EnterpriseUnit.EntGroupId), new[] {"Enterprise has no associated with it enterprise group"});
        }
        
    }
}
