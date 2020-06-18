namespace nscreg.Utilities.Configuration.StatUnitAnalysis
{
    /// <summary>
    /// Field of checking the binding of fields
    /// </summary>
    public class Orphan
    {
        //public bool CheckRelatedEnterpriseGroup { get; set; }
        public bool CheckOrphanLocalUnits { get; set; }
        public bool CheckOrphanLegalUnits { get; set; }
        public bool CheckLegalUnitRelatedLocalUnits { get; set; }
        public bool CheckEnterpriseRelatedLegalUnits { get; set; }
        public bool CheckOrphanEnterpriseGroups { get; set; }
    }
}
