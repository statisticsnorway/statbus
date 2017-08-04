namespace nscreg.Data.Entities
{
    public abstract class AnalysisError
    {
        public int Id { get; set; }
        public int AnalysisLogId { get; set; }
        public string ErrorKey { get; set; }
        public string ErrorValue { get; set; }
        public virtual AnalysisLog AnalysisLog { get; set; }
    }

    public class AnalysisStatisticalError : AnalysisError
    {
        public int StatisticalRegId { get; set; }
        public virtual StatisticalUnit StatisticalUnit { get; set; }
    }

    public class AnalysisGroupError : AnalysisError
    {
        public int GroupRegId { get; set; }
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }
    }
}
