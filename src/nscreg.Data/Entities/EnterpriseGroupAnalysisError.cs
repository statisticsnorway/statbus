namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность ошибка анализа группы предприятий
    /// </summary>
    public class EnterpriseGroupAnalysisError : AnalysisError
    {
        public int GroupRegId { get; set; }
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }
    }
}
