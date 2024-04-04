using nscreg.Business.Analysis.StatUnit;
using nscreg.Data.Entities;
using System.Threading.Tasks;

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
        Task<AnalysisResult> AnalyzeStatUnit(IStatisticalUnit unit, bool isAlterDataSourceAllowedOperation = false, bool isDataSourceUpload = false, bool isSkipCustomCheck = false);

        /// <summary>
        /// Analyzes stat units
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Task AnalyzeStatUnits(AnalysisQueue analysisQueue);
    }
}
