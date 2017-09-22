using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.Lookup
{
    /// <summary>
    /// Вью модель поиска единицы
    /// </summary>
    public class UnitLookupVm : CodeLookupVm, IUnitVm
    {
        public StatUnitTypes Type { get; set; }
    }
}
