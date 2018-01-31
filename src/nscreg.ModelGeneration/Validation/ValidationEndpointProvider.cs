using System.Collections.Generic;
using nscreg.Utilities.Enums;

namespace nscreg.ModelGeneration.Validation
{
    internal class ValidationEndpointProvider : IValidationEndpointProvider
    {
        private static readonly Dictionary<ValidationTypeEnum, string> Map;

        static ValidationEndpointProvider()
        {
            Map = new Dictionary<ValidationTypeEnum, string>()
            {
                [ValidationTypeEnum.StatIdUnique] = "/api/statunits/validatestatid"
            };
        }
      
        public string Get(ValidationTypeEnum? validationType)
        {
            return validationType.HasValue ? Map[validationType.Value] : null;
        }
    }
}
