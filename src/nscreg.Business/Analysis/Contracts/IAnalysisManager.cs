using System.Collections.Generic;

namespace nscreg.Business.Analysis.Contracts
{
    public interface IAnalysisManager
    {
        Dictionary<string, string[]> CheckFields();
    }
}
