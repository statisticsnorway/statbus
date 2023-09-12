using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Validators.Extensions
{
    /// <summary>
    /// Stat extension class. units
    /// </summary>
    public static class StatUnitExtension
    {
        /// <summary>
        /// Method for updating stat properties. units
        /// </summary>
        /// <param name = "statUnit"> </param>
        /// <param name = "model"> </param>
        /// <returns> </returns>
        public static StatisticalUnit UpdateProperties(this StatisticalUnit statUnit, PersonStatUnitModel model)
        {
            statUnit.Name = model.Name;
            statUnit.StatId = model.StatId;
            statUnit.TelephoneNo = model.TelephoneNo;
            statUnit.EmailAddress = model.EmailAddress;

            return statUnit;
        }

        /// <summary>
        /// Method for updating enterprise properties
        /// </summary>
        /// <param name = "statUnit"> </param>
        /// <param name = "model"> </param>
        /// <returns> </returns>
        public static EnterpriseGroup UpdateProperties(this EnterpriseGroup statUnit, PersonStatUnitModel model)
        {
            statUnit.Name = model.Name;
            statUnit.StatId = model.StatId;
            statUnit.TelephoneNo = model.TelephoneNo;
            statUnit.EmailAddress = model.EmailAddress;

            return statUnit;
        }
    }
}
