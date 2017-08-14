using Microsoft.Extensions.Configuration;

namespace nscreg.Business.Analysis.StatUnit.Rules
{
    /// <summary>
    /// Stat unit analysis rules container
    /// </summary>
    public class StatUnitAnalysisRules
    {
        public StatUnitAnalysisRules(IConfigurationSection mandatoryFieldsRules, IConfigurationSection connectionsRules,
            IConfigurationSection ophanRules,
            IConfigurationSection duplicatesRules)
        {
            MandatoryFieldsRules = mandatoryFieldsRules;
            ConnectionsRules = connectionsRules;
            OphanRules = ophanRules;
            DuplicatesRules = duplicatesRules;
        }

        public IConfigurationSection MandatoryFieldsRules { get; }
        public IConfigurationSection ConnectionsRules { get; }
        public IConfigurationSection OphanRules { get; }
        public IConfigurationSection DuplicatesRules { get; }
    }
}
