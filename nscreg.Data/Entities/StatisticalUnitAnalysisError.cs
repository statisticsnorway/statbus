namespace nscreg.Data.Entities
{
    public class StatisticalUnitAnalysisError : AnalysisError
    {
        public int StatisticalRegId { get; set; }
        public virtual StatisticalUnit StatisticalUnit { get; set; }
    }
}
