using nscreg.Business.Analysis.StatUnit;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.Contracts
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
        AnalysisResult AnalyzeStatUnit(IStatisticalUnit unit);

        /// <summary>
        /// Analyzes stat units
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        void AnalyzeStatUnits(AnalysisQueue analysisQueue);
    }
}
