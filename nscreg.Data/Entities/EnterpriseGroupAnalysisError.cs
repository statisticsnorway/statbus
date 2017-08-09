namespace nscreg.Data.Entities
{
    public class EnterpriseGroupAnalysisError : AnalysisError
    {
        public int GroupRegId { get; set; }
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }
    }
}
