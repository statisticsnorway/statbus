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

        public int? StatUnitId { get; set; }
        public virtual StatisticalUnit StatUnit { get; set; }

        public int? EnterpriseGroupId { get; set; }
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        public int? PersonId { get; set; }
        public virtual Person Person { get; set; }

        public PersonTypes PersonType { get; set; }
    }
}
