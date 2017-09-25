using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность персоны стат. единицы
    /// </summary>
    public class PersonStatisticalUnit
    {
        public int UnitId { get; set; }
        public virtual StatisticalUnit Unit { get; set; }

        public int PersonId { get; set; }
        public virtual Person Person { get; set; }

        public PersonTypes PersonType { get; set; }
    }
}
