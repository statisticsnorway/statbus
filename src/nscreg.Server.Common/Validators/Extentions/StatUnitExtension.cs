using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Validators.Extentions
{
    /// <summary>
    /// Класс расширения стат. единицы
    /// </summary>
    public static class StatUnitExtension
    {
        /// <summary>
        /// Метод обновления свойств стат. единицы
        /// </summary>
        /// <param name="statUnit"></param>
        /// <param name="model"></param>
        /// <returns></returns>
        public static StatisticalUnit UpdateProperties(this StatisticalUnit statUnit, StatUnitM model)
        {
            statUnit.Name = model.Name;
            statUnit.StatId = model.StatId;
            statUnit.TelephoneNo = model.TelephoneNo;
            statUnit.EmailAddress = model.EmailAddress;

            return statUnit;
        }

        /// <summary>
        /// Метод обновления свойств предприятия
        /// </summary>
        /// <param name="statUnit"></param>
        /// <param name="model"></param>
        /// <returns></returns>
        public static EnterpriseGroup UpdateProperties(this EnterpriseGroup statUnit, StatUnitM model)
        {
            statUnit.Name = model.Name;
            statUnit.StatId = model.StatId;
            statUnit.TelephoneNo = model.TelephoneNo;
            statUnit.EmailAddress = model.EmailAddress;

            return statUnit;
        }
    }
}
