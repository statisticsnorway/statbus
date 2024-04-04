using System.Collections.Generic;
using nscreg.Data.Entities;
using nscreg.Business.Analysis.StatUnit;
using System.Threading.Tasks;

namespace nscreg.Business.Analysis.Contracts
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
        Task<Dictionary<string, string[]>> CheckConnections(IStatisticalUnit unit);

        /// <summary>
        /// Analyzes stat unit's mandatory fields
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<string, string[]> CheckMandatoryFields(IStatisticalUnit unit);
        
        /// <summary>
        /// Analyze calculation fields
        /// </summary>
        /// <param name="unit"></param>
        /// <returns></returns>
       Dictionary<string, string[]> CheckCalculationFields(IStatisticalUnit unit);

        /// <summary>
        /// Analyze stat unit for duplicates
        /// </summary>
        /// <param name="unit"></param>
        /// <param name="units"></param>
        /// <returns></returns>
        Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit, List<AnalysisDublicateResult> units);

        /// <summary>
        /// Analyzes stat unit for all checks
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Task<AnalysisResult> CheckAll(IStatisticalUnit unit);
    }
}
