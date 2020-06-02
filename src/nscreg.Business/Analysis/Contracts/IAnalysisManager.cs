using System.Collections.Generic;

namespace nscreg.Business.Analysis.Contracts
{
    /// <summary>
    /// Analysis managers interface
    /// </summary>
    public interface IAnalysisManager
    {
        Dictionary<string, string[]> CheckFields();
    }

    public interface IMandatoryFieldsAnalysisManager : IAnalysisManager
    {
        Dictionary<string, string[]> CheckOnlyIdentifiersFields();
    }
}
