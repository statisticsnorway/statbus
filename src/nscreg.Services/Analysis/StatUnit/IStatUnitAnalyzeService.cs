using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Services.Analysis.StatUnit
{
    /// <summary>
    /// Interface for stat unit analyze service
    /// </summary>
    public interface IStatUnitAnalyzeService
    {
        /// <summary>
        /// Analyzes stat unit
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<int, Dictionary<string, string[]>> AnalyzeStatUnit(IStatisticalUnit unit);

        /// <summary>
        /// Analyzes stat units
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<int, Dictionary<string, string[]>> AnalyzeStatUnits(List<(int regId, StatUnitTypes unitType)> units);

        /// <summary>
        /// Analyzes stat unit for duplicates
        /// </summary>
        /// <param name="unit"></param>
        /// <returns></returns>
        List<IStatisticalUnit> AnalyzeStatUnitForDuplicates(IStatisticalUnit unit);
    }
}