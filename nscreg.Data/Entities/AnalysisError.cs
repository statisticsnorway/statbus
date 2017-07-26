namespace nscreg.Data.Entities
{
    public class AnalysisError
    {
        public int AnalysisLogId { get; set; }
        public int RegId { get; set; }
        public string ErrorKey { get; set; }
        public string ErrorValue { get; set; }
        public virtual AnalysisLog AnalysisLog { get; set; }
        public virtual StatisticalUnit StatisticalUnit { get; set; }
    }
}
