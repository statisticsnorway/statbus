namespace nscreg.Utilities.Configuration.StatUnitAnalysis
{
    /// <summary>
    /// Класс проверки правил анализа стат. едениц
    /// </summary>
    public class StatUnitAnalysisRules
    {
        public Connections Connections { get; set; }
        public Orphan Orphan { get; set; }
        public Duplicates Duplicates { get; set; }
        public CalculationFields CalculationFields { get; set; }
    }
}
