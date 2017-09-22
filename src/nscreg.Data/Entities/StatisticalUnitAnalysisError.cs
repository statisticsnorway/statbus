namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность ошибка анализа стат. единицы
    /// </summary>
    public class StatisticalUnitAnalysisError : AnalysisError
    {
        public int StatisticalRegId { get; set; }
        public virtual StatisticalUnit StatisticalUnit { get; set; }
    }
}
