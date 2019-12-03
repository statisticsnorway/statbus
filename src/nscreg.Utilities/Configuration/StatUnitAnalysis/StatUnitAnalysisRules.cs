namespace nscreg.Utilities.Configuration.StatUnitAnalysis
{
    /// <summary>
    /// Class for checking the rules of analysis stat. unit
    /// </summary>
    public class StatUnitAnalysisRules
    {
        public Connections Connections { get; set; }
        public Orphan Orphan { get; set; }
        public Duplicates Duplicates { get; set; }
        public bool CustomAnalysisChecks { get; set; }
    }
}
