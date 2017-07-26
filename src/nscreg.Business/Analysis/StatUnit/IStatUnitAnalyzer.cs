using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.Business.Analysis.StatUnit
{
    /// <summary>
    /// Interface for stat unit analyzer
    /// </summary>
    public interface IStatUnitAnalyzer
    {
        /// <summary>
        /// Analyzes stat unit's connections and addresses
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<string, string[]> CheckConnections(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses);

        /// <summary>
        /// Analyzes stat unit's mandatory fields
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<string, string[]> CheckMandatoryFields(IStatisticalUnit unit);

        /// <summary>
        /// Analyzes stat unit for orphaness
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<string, string[]> CheckOrphanUnits(IStatisticalUnit unit);

        /// <summary>
        /// Analyze stat unit for duplicates
        /// </summary>
        /// <param name="unit"></param>
        /// <param name="units"></param>
        /// <returns></returns>
        Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit, List<StatisticalUnit> units);

        /// <summary>
        /// Analyzes stat unit for all checks
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<int, AnalysisResult> CheckAll(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses, List<StatisticalUnit> units);

        
    }
}
