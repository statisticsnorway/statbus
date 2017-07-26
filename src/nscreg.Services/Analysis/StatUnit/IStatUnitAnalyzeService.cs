using System;
using System.Collections.Generic;
using nscreg.Business.Analysis.StatUnit;
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
        Dictionary<int, AnalysisResult> AnalyzeStatUnit(IStatisticalUnit unit);

        /// <summary>
        /// Analyzes stat units
        /// </summary>
        /// <returns>List of messages with warnings</returns>
        Dictionary<int, AnalysisResult> AnalyzeStatUnits(List<Tuple<int, StatUnitTypes>> units);
    }
}